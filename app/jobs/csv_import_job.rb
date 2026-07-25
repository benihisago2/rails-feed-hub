require "csv"
require "tempfile"

# Runs one bulk feed import in the background.
#
# The job owns everything to do with the *file*: finding the attachment, getting
# characters out of it and turning those characters into rows. What a row means
# belongs to FeedCsvImporter.
class CsvImportJob < ApplicationJob
  queue_as :imports

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

    # Stream the attachment to a tempfile and read it a row at a time. The whole
    # file is never resident as one String and the parsed rows are never
    # materialised into one Array, so import memory no longer scales with the
    # row count. CSV.foreach without a block returns a lazy enumerator, which is
    # exactly the "any enumerable of rows" the importer already expects.
    #
    # "bom|utf-8" makes CSV detect and drop the UTF-8 byte order mark Excel
    # writes at the start of a file. Left in place it becomes part of the first
    # header ("﻿title"), and every lookup of "title" returns nil.
    tempfile = download_to_tempfile(import_job)

    rows = CSV.foreach(tempfile.path, headers: true, encoding: "bom|utf-8")
    FeedCsvImporter.new(import_job, rows).call
  rescue StandardError => e
    Rails.logger.error("CsvImportJob failed import_job_id=#{import_job_id} error=#{e.class}: #{e.message}")

    # Remove the tempfile we streamed the upload into.
    tempfile&.close!

    # A failure raised before the importer took over -- a download that did not
    # come back, a file that is not CSV at all -- would otherwise leave the row
    # stuck on "running" forever.
    import_job.update!(status: :failed) if import_job && !import_job.failed?
    raise
  end

  private

  # Streams the attachment down in chunks so the whole blob is never held in
  # memory at once, and returns the tempfile it was written to.
  def download_to_tempfile(import_job)
    tempfile = Tempfile.new([ "feed_import", ".csv" ], binmode: true)
    import_job.file.download { |chunk| tempfile.write(chunk) }
    tempfile.flush
    tempfile
  end
end
