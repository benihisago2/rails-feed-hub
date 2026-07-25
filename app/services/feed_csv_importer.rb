# Turns the rows of an uploaded CSV into Feed records and records what happened
# on the ImportJob that owns the upload.
#
# The service is handed rows, not a file. Reading the attachment is CsvImportJob's
# problem: how the bytes arrive (a whole String, a streamed parse, a fixture in a
# spec) has nothing to do with what a row means, and keeping the two apart means
# the reading strategy can change without touching any of the row logic below.
#
# The central design decision is that there is **no wrapping transaction**. A CSV
# an operator uploaded is not an atomic unit of intent -- it is a list of things
# they want registered. Rolling back 997 good rows because 3 were mistyped throws
# away work the operator would only have to redo, and tells them nothing about
# which 3 were wrong. Each row is committed on its own and every rejection is
# written to error_report with the line number it came from, so the fix is
# "correct three lines and re-upload", not "find the mistake and start over".
class FeedCsvImporter
  # Base class for the failures this service raises. There is nothing under it
  # yet: every *row* problem is data, recorded and stepped over, not an
  # exception. The class exists so a caller has something to rescue if a later
  # phase adds a genuine service-level failure.
  class Error < StandardError; end

  # What one run did, from the caller's point of view. skipped_count is reported
  # separately from error_count on purpose -- see #import_row.
  Result = Data.define(:import_job_id, :total_count, :success_count, :skipped_count, :error_count)

  # Columns the importer reads. Anything else in the file is ignored, so a CSV
  # exported from somewhere else does not have to be trimmed before upload.
  TITLE_COLUMN = "title".freeze
  URL_COLUMN = "url".freeze
  ACTIVE_COLUMN = "active".freeze

  # The file has a header row, so the first row of data is line 2. error_report
  # quotes the line number of the *file*, because that is the number the
  # operator's editor shows them.
  HEADER_LINE_COUNT = 1

  # Accepted spellings for the boolean column. An unrecognised value is a row
  # error rather than a silent cast: "activ" or "1 " should not quietly become
  # true, because the operator would never find out the feed is switched on.
  TRUE_VALUES = %w[true t yes y 1].freeze
  FALSE_VALUES = %w[false f no n 0].freeze
  ACCEPTED_BOOLEANS = (TRUE_VALUES + FALSE_VALUES).join(", ").freeze

  # rows is any enumerable of objects that answer to #[] with a column name --
  # CSV::Row satisfies it, and so does a plain Hash in a spec.
  def initialize(import_job, rows)
    @import_job = import_job
    @rows = rows
    @total_count = 0
    @success_count = 0
    @skipped_count = 0
    @error_count = 0
    @error_report = []
  end

  # Returns a Result. Only an exception that escapes the whole run -- not a bad
  # row, which is expected -- marks the ImportJob failed, and that exception is
  # re-raised so the job backend can retry it or park it where a human sees it.
  def call
    rows.each_with_index { |row, index| import_row(row, line_number(index)) }

    finish(:completed)

    Result.new(
      import_job_id: import_job.id,
      total_count: total_count,
      success_count: success_count,
      skipped_count: skipped_count,
      error_count: error_count
    )
  rescue StandardError => e
    Rails.logger.error(
      "FeedCsvImporter failed import_job_id=#{import_job.id} row=#{total_count} " \
      "error=#{e.class}: #{e.message}"
    )

    finish(:failed)
    raise
  end

  private

  attr_reader :import_job, :rows, :total_count, :success_count, :skipped_count, :error_count, :error_report

  def line_number(index)
    index + 1 + HEADER_LINE_COUNT
  end

  def import_row(row, line)
    @total_count += 1

    url = value(row, URL_COLUMN)
    active = boolean(value(row, ACTIVE_COLUMN))

    # The only value the file can get *syntactically* wrong. Everything else is
    # handed to the model, which already owns the rules.
    if active == :invalid
      return record_error(line, url, "active must be one of #{ACCEPTED_BOOLEANS}")
    end

    feed = Feed.new(title: value(row, TITLE_COLUMN), url: url)
    feed.active = active unless active.nil?

    if feed.save
      @success_count += 1
    elsif duplicate_url_only?(feed)
      # A url that is already registered is not a mistake worth reporting. Feeds
      # are re-imported constantly -- an operator re-uploads last month's list
      # with five new lines appended -- and if that counted as 95 errors the
      # error report would be noise and nobody would read the five real ones.
      # The row is counted, and deliberately kept out of error_count.
      @skipped_count += 1
    else
      record_error(line, url, feed.errors.full_messages.join(", "))
    end
  end

  def value(row, column)
    # A row with fewer fields than the header returns nil for the missing ones,
    # which lands here as nil and is rejected by the model's presence rules.
    row[column]&.to_s&.strip.presence
  end

  # Returns true, false, nil (column absent -- let the column default stand), or
  # :invalid.
  def boolean(raw)
    return nil if raw.nil?

    downcased = raw.downcase
    return true if TRUE_VALUES.include?(downcased)
    return false if FALSE_VALUES.include?(downcased)

    :invalid
  end

  # True when the *only* thing wrong with the row is that the url is already
  # registered. A row that is both duplicated and malformed is still an error:
  # the operator wrote something they need to see.
  def duplicate_url_only?(feed)
    feed.errors.attribute_names == [ :url ] &&
      feed.errors.details[:url].map { |detail| detail[:error] } == [ :taken ]
  end

  def record_error(line, url, message)
    @error_count += 1
    @error_report << { "line" => line, "url" => url, "message" => message }
  end

  # The counters are written once, at the end, rather than after every row. A
  # thousand-row file would otherwise issue a thousand UPDATEs against the same
  # row for numbers nobody reads until the import is over.
  def finish(status)
    import_job.update!(
      status: status,
      total_count: total_count,
      success_count: success_count,
      error_count: error_count,
      error_report: error_report
    )
  end
end
