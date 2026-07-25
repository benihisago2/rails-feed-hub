require "rails_helper"
require "csv"

RSpec.describe CsvImportJob do
  include ActiveJob::TestHelper

  # The three bytes Excel puts at the front of a UTF-8 CSV. Spelled out as bytes
  # rather than as the character, which is zero width and would be invisible in
  # this file.
  let(:bom) { "\xEF\xBB\xBF" }

  let(:import_job) { create(:import_job) }

  def attach(content, filename: "feeds.csv")
    import_job.file.attach(
      io: StringIO.new(content),
      filename: filename,
      content_type: "text/csv"
    )
  end

  it "runs on the imports queue" do
    expect(described_class.new.queue_name).to eq("imports")
  end

  describe "enqueueing" do
    it "carries the import job id rather than the record" do
      import_job_id = import_job.id

      expect { described_class.perform_later(import_job_id) }
        .to have_enqueued_job(described_class).with(import_job_id).on_queue("imports")
    end
  end

  describe "#perform" do
    it "imports the attached file" do
      attach(<<~CSV)
        title,url,active
        Rails Blog,https://rubyonrails.org/feed.xml,true
      CSV

      expect { described_class.perform_now(import_job.id) }.to change(Feed, :count).by(1)

      expect(import_job.reload).to have_attributes(
        status: "completed",
        total_count: 1,
        success_count: 1,
        error_count: 0
      )
    end

    it "records partial failure without losing the good rows" do
      attach(<<~CSV)
        title,url,active
        Good One,https://example.com/one.xml,true
        ,https://example.com/two.xml,true
        Good Three,https://example.com/three.xml,true
      CSV

      described_class.perform_now(import_job.id)

      expect(import_job.reload).to have_attributes(
        status: "completed",
        total_count: 3,
        success_count: 2,
        error_count: 1
      )
      expect(Feed.pluck(:title)).to match_array([ "Good One", "Good Three" ])
    end

    it "strips the byte order mark a file exported from Excel starts with" do
      attach(bom + <<~CSV)
        title,url,active
        Rails Blog,https://rubyonrails.org/feed.xml,true
      CSV

      described_class.perform_now(import_job.id)

      # Without the strip the first header is not "title", so the title of every
      # row reads as blank and the whole file is rejected.
      expect(Feed.find_by(url: "https://rubyonrails.org/feed.xml").title).to eq("Rails Blog")
      expect(import_job.reload).to have_attributes(status: "completed", success_count: 1, error_count: 0)
    end

    it "does nothing when the import job no longer exists" do
      missing_id = ImportJob.maximum(:id).to_i + 1

      expect { described_class.perform_now(missing_id) }.not_to change(Feed, :count)
    end

    it "marks the import failed when no file was ever attached" do
      described_class.perform_now(import_job.id)

      expect(import_job.reload.status).to eq("failed")
    end

    it "marks the import failed and re-raises when the file is not readable as CSV" do
      attach(<<~CSV)
        title,url,active
        Broken,"https://example.com/one.xml"x,true
      CSV

      expect { described_class.perform_now(import_job.id) }.to raise_error(CSV::MalformedCSVError)

      expect(import_job.reload.status).to eq("failed")
    end

    it "moves the import to running before handing it to the importer" do
      attach("title,url,active\n")
      statuses = []
      allow(FeedCsvImporter).to receive(:new) do |job, _rows|
        statuses << job.status
        instance_double(FeedCsvImporter, call: nil)
      end

      described_class.perform_now(import_job.id)

      expect(statuses).to eq([ "running" ])
    end
  end
end
