require "net/http"
require "rss"
require "securerandom"
require "uri"

# Fetches a single feed over HTTP, parses the RSS or Atom document it returns
# and stores the entries as articles.
#
# The service owns the whole cycle for one feed: the request, the parse, the
# write, and the bookkeeping on the feed row. It knows nothing about scheduling
# or retrying -- FetchFeedJob supplies both. That split is what lets a feed be
# re-fetched in isolation without touching any other feed.
class FeedFetcher
  # Base class for every failure this service raises. FetchFeedJob keys its
  # retry rule off this class, so anything worth retrying has to descend from it.
  class Error < StandardError; end

  # The host accepted the connection but did not answer inside the timeouts.
  class TimeoutError < Error; end

  # The request never got far enough to produce a response at all.
  class ConnectionError < Error; end

  # The host answered with something other than 2xx.
  class HttpError < Error
    attr_reader :status

    def initialize(status, url)
      @status = status
      super("GET #{url} returned HTTP #{status}")
    end
  end

  # A body came back, but it is not a feed this parser can read.
  class ParseError < Error; end

  # What one call did, from the caller's point of view. `created_count` counts
  # only the articles that did not exist before this fetch, which is the number
  # a caller (or an operator reading the logs) actually cares about.
  Result = Data.define(:feed_id, :entry_count, :created_count)

  # One feed entry, flattened so the storage code never has to ask whether the
  # document was RSS or Atom.
  Entry = Data.define(:guid, :title, :url, :summary, :published_at)

  # Explicit timeouts, in seconds. Without them Net::HTTP inherits defaults
  # measured in minutes, and one unresponsive host would occupy a Sidekiq
  # thread long enough to matter.
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10

  USER_AGENT = "FeedHub/1.0".freeze

  # Failures raised before any response exists. Every one of them is a plain
  # "the network did not work" condition and is worth retrying later.
  CONNECTION_ERRORS = [
    SocketError,
    IOError,
    SystemCallError,
    Net::HTTPBadResponse,
    Net::ProtocolError
  ].freeze

  # Columns refreshed when an entry we already stored comes back changed.
  # created_at is deliberately absent: it records when we first saw the entry,
  # and an upsert must not rewrite that.
  UPDATABLE_COLUMNS = %i[title url summary published_at updated_at].freeze

  def initialize(feed)
    @feed = feed
  end

  # Returns a Result. Raises a FeedFetcher::Error subclass on any failure,
  # after recording the reason on the feed.
  def call
    entries = parse(fetch_body)
    created_count = store(entries)
    mark_success

    Result.new(feed_id: feed.id, entry_count: entries.size, created_count: created_count)
  rescue StandardError => e
    mark_failure(e)
    raise
  end

  private

  attr_reader :feed

  def fetch_body
    uri = URI.parse(feed.url)
    response = perform_request(uri)

    raise HttpError.new(response.code.to_i, feed.url) unless response.is_a?(Net::HTTPSuccess)

    # Net::HTTP returns the body as ASCII-8BIT. The parser works on characters,
    # and feeds are UTF-8 in practice; anything else fails in the parse step,
    # where it is reported as a parse error rather than as a mystery.
    response.body.to_s.dup.force_encoding(Encoding::UTF_8)
  end

  # The HTTP call lives here, inline, rather than behind a collaborator. There
  # is exactly one caller today and the whole conversation is six lines long.
  def perform_request(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = USER_AGENT
    request["Accept"] = "application/rss+xml, application/atom+xml, application/xml;q=0.9, */*;q=0.8"

    http.request(request)
  rescue Timeout::Error => e
    raise TimeoutError, "GET #{feed.url} timed out after open=#{OPEN_TIMEOUT}s read=#{READ_TIMEOUT}s (#{e.class})"
  rescue *CONNECTION_ERRORS => e
    raise ConnectionError, "GET #{feed.url} failed: #{e.class}: #{e.message}"
  end

  def parse(body)
    # Validation is off, and unknown elements are ignored. Feeds in the wild
    # bend the specification constantly -- a namespaced extension or a missing
    # optional element is not a reason to throw away a readable document. The
    # parser is configured through the instance rather than through
    # RSS::Parser.parse so the two flags are named where they are set.
    parser = RSS::Parser.new(body)
    parser.do_validate = false
    parser.ignore_unknown_element = true

    parsed = parser.parse
    raise ParseError, "#{feed.url} did not return a recognisable RSS or Atom document" if parsed.nil?

    if parsed.is_a?(RSS::Atom::Feed)
      parsed.items.map { |entry| atom_entry(entry) }
    else
      parsed.items.map { |item| rss_entry(item) }
    end
  rescue RSS::Error => e
    raise ParseError, "#{feed.url} could not be parsed: #{e.class}: #{e.message}"
  end

  # RSS 2.0 and RSS 1.0 (RDF) both land here. Their item elements differ enough
  # that the two identifier and date accessors are asked for by name.
  def rss_entry(item)
    Entry.new(
      guid: identifier(rss_identifier(item)),
      title: item.title.to_s.strip,
      url: item.link.to_s.strip,
      summary: item.description,
      published_at: item.respond_to?(:pubDate) ? item.pubDate : item.dc_date
    )
  end

  def rss_identifier(item)
    # RSS 1.0 has no <guid>; an item is identified by its rdf:about attribute.
    return item.about unless item.respond_to?(:guid)

    item.guid&.content
  end

  def atom_entry(entry)
    Entry.new(
      guid: identifier(entry.id&.content),
      title: entry.title&.content.to_s.strip,
      url: entry.link&.href.to_s.strip,
      summary: entry.summary&.content || entry.content&.content,
      published_at: (entry.published || entry.updated)&.content
    )
  end

  # The identifier the feed publishes for an entry, or a generated one when the
  # feed publishes none. The guid column is NOT NULL and carries the unique
  # index, so every row has to arrive with a value.
  def identifier(published_identifier)
    published_identifier.presence || SecureRandom.uuid
  end

  def store(entries)
    rows = build_rows(entries)
    return 0 if rows.empty?

    # Deduplication is the database's job. Two workers can fetch the same feed
    # at the same moment, so "does this guid exist?" followed by an INSERT
    # always leaves a race window open; ON CONFLICT against the unique index on
    # (feed_id, guid) does not.
    #
    # upsert_all reports the rows it touched, not the rows it inserted, so the
    # number of genuinely new articles is measured around the write.
    before = feed.articles.count

    Article.upsert_all(
      rows,
      unique_by: %i[feed_id guid],
      update_only: UPDATABLE_COLUMNS,
      record_timestamps: false
    )

    feed.articles.count - before
  end

  def build_rows(entries)
    # upsert_all bypasses callbacks and timestamp handling, so both timestamps
    # are supplied here. One value for the whole batch keeps the rows of a
    # single fetch comparable.
    now = Time.current

    rows = entries.filter_map do |entry|
      # title and url are NOT NULL. An entry missing either is not storable,
      # and dropping it beats failing the whole fetch.
      next if entry.title.blank? || entry.url.blank?

      {
        feed_id: feed.id,
        guid: entry.guid,
        title: entry.title,
        url: entry.url,
        summary: entry.summary,
        published_at: entry.published_at,
        created_at: now,
        updated_at: now
      }
    end

    # A document that repeats a guid would make PostgreSQL reject the entire
    # statement: ON CONFLICT DO UPDATE cannot affect the same row twice.
    rows.uniq { |row| row[:guid] }
  end

  def mark_success
    feed.update!(last_fetched_at: Time.current, last_status: :ok, last_error: nil)
  end

  # last_fetched_at is left alone on purpose: it answers "when did we last have
  # good data from this feed?", and a failed attempt did not produce any.
  def mark_failure(error)
    Rails.logger.error(
      "FeedFetcher failed feed_id=#{feed.id} url=#{feed.url} error=#{error.class}: #{error.message}"
    )

    feed.update!(
      last_status: :failed,
      last_error: "#{error.class}: #{error.message}".truncate(1_000)
    )
  end
end
