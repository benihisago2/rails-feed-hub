require "net/http"
require "uri"

# Fetches the raw body of a feed over HTTP.
#
# This is the transport half of what FeedFetcher used to do inline: it owns the
# Net::HTTP setup -- timeouts, headers, the SSL toggle -- sends the request, and
# hands back the decoded body. It knows nothing about RSS, Atom, articles or the
# feed row; FeedFetcher keeps all of that. Splitting the transport out gives the
# fetcher a collaborator it can be handed, so the parse/store path can be tested
# with a fake client and no network stub at all.
class FeedHttpClient
  # Explicit timeouts, in seconds. Without them Net::HTTP inherits defaults
  # measured in minutes, and one unresponsive host would occupy a Sidekiq thread
  # long enough to matter.
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

  # Returns the response body as a UTF-8 string, or raises one of
  # FeedFetcher's error classes.
  def call(feed)
    uri = URI.parse(feed.url)
    response = perform_request(uri, feed.url)

    raise FeedFetcher::HttpError.new(response.code.to_i, feed.url) unless response.is_a?(Net::HTTPSuccess)

    # Net::HTTP returns the body as ASCII-8BIT. The parser works on characters,
    # and feeds are UTF-8 in practice; anything else fails in the parse step,
    # where it is reported as a parse error rather than as a mystery.
    response.body.to_s.dup.force_encoding(Encoding::UTF_8)
  end

  private

  def perform_request(uri, url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = USER_AGENT
    request["Accept"] = "application/rss+xml, application/atom+xml, application/xml;q=0.9, */*;q=0.8"

    http.request(request)
  rescue Timeout::Error => e
    raise FeedFetcher::TimeoutError, "GET #{url} timed out after open=#{OPEN_TIMEOUT}s read=#{READ_TIMEOUT}s (#{e.class})"
  rescue *CONNECTION_ERRORS => e
    raise FeedFetcher::ConnectionError, "GET #{url} failed: #{e.class}: #{e.message}"
  end
end
