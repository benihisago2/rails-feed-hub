# Upload a CSV of feeds and watch the import that follows.
class ImportJobsController < ApplicationController
  def index
    @import_jobs = ImportJob.order(created_at: :desc)

    # The templates arrive in phase 5. Until then the actions answer with a
    # status so the routes and the queries are exercised rather than guessed at.
    head :ok
  end

  def show
    @import_job = ImportJob.find(params[:id])

    head :ok
  end

  def create
    upload = import_job_params[:file]

    if upload.blank?
      redirect_to import_jobs_path, alert: "Choose a CSV file to import."
      return
    end

    import_job = ImportJob.new(filename: upload.original_filename)
    import_job.file.attach(upload)
    import_job.save!

    # Enqueue and return. The import is never run inline: a request thread that
    # parses the file holds a connection and a Puma worker for as long as the
    # file is long, and a ten thousand row upload would sit past the proxy's
    # timeout and hand the operator a 502 for an import that actually succeeded.
    # Handing the work to Sidekiq makes the response time a property of the
    # upload size alone, and gives the import somewhere to be retried from.
    CsvImportJob.perform_later(import_job.id)

    redirect_to import_job_path(import_job), notice: "Import started. This page shows its progress."
  end

  private

  def import_job_params
    params.fetch(:import_job, {}).permit(:file)
  end
end
