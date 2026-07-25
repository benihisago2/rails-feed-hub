require "csv"

# Runs one bulk feed import in the background.
#
# The job owns everything to do with the *file*: finding the attachment, getting
# characters out of it and turning those characters into rows. What a row means
# belongs to FeedCsvImporter.
class CsvImportJob < ApplicationJob
  queue_as :imports

  # Excel writes a UTF-8 byte order mark at the start of every CSV it exports.
  # Left in place it becomes part of the first header, which then reads
  # "\uFEFFtitle" instead of "title". Every lookup of "title" would return nil,
  # and a file that looks perfectly fine in a spreadsheet would import as N rows
  # with no title at all. Written as an escape because the character itself is
  # zero-width and would be invisible in this file.
  BOM = "\uFEFF".freeze

  # The argument is the id, not the record: the payload in Redis stays small and
  # the worker reads the current state of the row rather than a copy of how it
  # looked when the controller enqueued the job.
  def perform(import_job_id)
    import_job = ImportJob.find_by(id: import_job_id)

    # Deleted between enqueue and execution. There is nothing to import and
    # nothing to report it on, so this is not a failure.
    if import_job.nil?
      Rails.logger.warn("CsvImportJob skipped: import_job_id=#{import_job_id} no longer exists")
      return
    end

    # No attachment means the upload never completed. Retrying cannot make a
    # file appear, so the row is marked failed and the job stops here.
    unless import_job.file.attached?
      Rails.logger.error("CsvImportJob failed: import_job_id=#{import_job.id} has no attached file")
      import_job.update!(status: :failed)
      return
    end

    import_job.update!(status: :running)

    FeedCsvImporter.new(import_job, read_rows(import_job)).call
  rescue StandardError => e
    Rails.logger.error("CsvImportJob failed import_job_id=#{import_job_id} error=#{e.class}: #{e.message}")

    # A failure raised before the importer took over -- a download that did not
    # come back, a file that is not CSV at all -- would otherwise leave the row
    # stuck on "running" forever.
    import_job.update!(status: :failed) if import_job && !import_job.failed?
    raise
  end

  private

  # Reads the attachment and hands back its rows.
  def read_rows(import_job)
    content = import_job.file.download.to_s.dup.force_encoding(Encoding::UTF_8)

    CSV.parse(content.delete_prefix(BOM), headers: true)
  end
end
