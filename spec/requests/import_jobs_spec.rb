require "rails_helper"

RSpec.describe "ImportJobs" do
  # A real multipart upload rather than a stubbed one: the point of the create
  # action is that the bytes make it into Active Storage before the response is
  # written, and only an actual uploaded file exercises that.
  def csv_upload(content = "title,url,active\nRails Blog,https://rubyonrails.org/feed.xml,true\n")
    Rack::Test::UploadedFile.new(StringIO.new(content), "text/csv", original_filename: "feeds.csv")
  end

  describe "GET /import_jobs" do
    it "shows the upload form and the history" do
      create(:import_job, filename: "january.csv", status: :completed, total_count: 12, success_count: 11, error_count: 1)

      get import_jobs_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("january.csv", "completed")
      expect(response.body).to include("import_job_file")
    end
  end

  describe "GET /import_jobs/:id" do
    it "shows the counts and the rejected rows" do
      import_job = create(
        :import_job,
        filename: "january.csv",
        status: :completed,
        total_count: 2,
        success_count: 1,
        error_count: 1,
        error_report: [ { "line" => 3, "url" => "not-a-url", "message" => "Url is invalid" } ]
      )

      get import_job_path(import_job)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("january.csv", "not-a-url", "Url is invalid")
    end

    it "says so plainly when no row was rejected" do
      import_job = create(:import_job, status: :completed, error_report: [])

      get import_job_path(import_job)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No rows were rejected.")
    end
  end

  describe "POST /import_jobs" do
    it "stores the upload, hands the parsing to a job and redirects" do
      # The assertion stops at "the job was enqueued" on purpose. Whether the
      # rows parse is CsvImportJob's and FeedCsvImporter's contract, tested
      # where those live; this action's job is to persist the file and return.
      expect { post import_jobs_path, params: { import_job: { file: csv_upload } } }
        .to have_enqueued_job(CsvImportJob).on_queue("imports")

      import_job = ImportJob.last
      expect(import_job).to have_attributes(filename: "feeds.csv", status: "pending")
      expect(import_job.file).to be_attached
      expect(response).to redirect_to(import_job_path(import_job))
    end

    it "asks for a file instead of creating an empty import" do
      expect { post import_jobs_path, params: { import_job: {} } }.not_to change(ImportJob, :count)

      expect(response).to redirect_to(import_jobs_path)
      expect(flash[:alert]).to eq("Choose a CSV file to import.")
    end
  end
end
