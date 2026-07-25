require "csv"

# Renders articles as CSV.
#
# The result is an Enumerator of finished CSV lines rather than one String. An
# export is the one place in this application where the size of the answer is
# unbounded -- it grows with every fetch, forever -- so nothing here is allowed
# to hold the whole result set at once: find_each walks the table in batches and
# each line is yielded and forgotten.
class ArticleCsvExporter
  HEADERS = %w[feed_title title url published_at tags].freeze

  # Rows loaded per query. Large enough that the round trips do not dominate,
  # small enough that one batch is never the thing that fills the heap.
  BATCH_SIZE = 500

  # Commas are already spoken for by the format, so tags are joined with a
  # semicolon. A reader can split on it without a CSV parser.
  TAG_SEPARATOR = ";".freeze

  # The scope is injected so the same exporter serves "everything" and whatever
  # the articles index is currently filtered to.
  def initialize(scope = Article.all)
    @scope = scope
  end

  # Returns an Enumerator that yields one CSV line at a time, header first.
  # Nothing is queried until the caller starts consuming it.
  def call
    Enumerator.new do |yielder|
      yielder << CSV.generate_line(HEADERS)

      # find_each imposes its own ordering by primary key and ignores any other,
      # which is exactly what makes batching safe: rows cannot shift between
      # batches and be exported twice or skipped.
      #
      # includes() is preloaded per batch, so the feed title and the tag names of
      # 500 articles cost two extra queries per batch rather than 1000.
      scope.includes(:feed, :tags).find_each(batch_size: BATCH_SIZE) do |article|
        yielder << CSV.generate_line(row_for(article))
      end
    end
  end

  private

  attr_reader :scope

  def row_for(article)
    [
      article.feed.title,
      article.title,
      article.url,
      # ISO 8601 so the column is unambiguous to whatever reads it next. nil
      # stays nil and CSV writes an empty field -- not "", not a fake epoch.
      article.published_at&.iso8601,
      # Sorted so re-exporting the same data produces the same bytes; the tags
      # are already loaded, so this does not touch the database.
      #
      # presence, not the bare join: CSV writes "" as a quoted empty string and
      # nil as an empty field. An untagged article should look the same as an
      # article with no published_at, not carry a stray pair of quotes.
      article.tags.map(&:name).sort.join(TAG_SEPARATOR).presence
    ]
  end
end
