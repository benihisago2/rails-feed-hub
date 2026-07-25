require "rails_helper"
require "csv"

RSpec.describe FeedCsvImporter do
  let(:import_job) { create(:import_job, status: :running) }

  # The importer is given rows, not a file, so the specs build rows the same way
  # the job does and nothing here has to touch Active Storage.
  def import(csv)
    described_class.new(import_job, CSV.parse(csv, headers: true)).call
  end

  def csv_with(*lines)
    ([ "title,url,active" ] + lines).join("\n") + "\n"
  end

  describe "#call" do
    context "when every row is valid" do
      let(:ten_good_rows) do
        csv_with(*Array.new(10) { |i| "Feed #{i + 1},https://example.com/feeds/#{i + 1}.xml,true" })
      end

      it "creates one feed per row" do
        expect { import(ten_good_rows) }.to change(Feed, :count).by(10)
      end

      it "reports every row as a success" do
        expect(import(ten_good_rows)).to have_attributes(
          import_job_id: import_job.id,
          total_count: 10,
          success_count: 10,
          skipped_count: 0,
          error_count: 0
        )
      end

      it "writes the counts and the completed status onto the import job" do
        import(ten_good_rows)

        expect(import_job.reload).to have_attributes(
          status: "completed",
          total_count: 10,
          success_count: 10,
          error_count: 0,
          error_report: []
        )
      end

      it "copies the columns of a row onto the feed" do
        import(csv_with("Rails Blog,https://rubyonrails.org/feed.xml,false"))

        expect(Feed.find_by(url: "https://rubyonrails.org/feed.xml"))
          .to have_attributes(title: "Rails Blog", active: false)
      end

      it "leaves active at the column default when the field is empty" do
        import(csv_with("Rails Blog,https://rubyonrails.org/feed.xml,"))

        expect(Feed.find_by(url: "https://rubyonrails.org/feed.xml").active).to be(true)
      end

      it "trims surrounding whitespace" do
        import(csv_with("  Rails Blog  ,  https://rubyonrails.org/feed.xml  ,true"))

        expect(Feed.find_by(url: "https://rubyonrails.org/feed.xml").title).to eq("Rails Blog")
      end
    end

    context "when some rows are invalid" do
      # Lines 4, 7 and 10 of the file are bad: no title, a url that is not a
      # url, and no url at all.
      let(:ten_rows_three_bad) do
        csv_with(
          "Feed 1,https://example.com/feeds/1.xml,true",
          "Feed 2,https://example.com/feeds/2.xml,true",
          ",https://example.com/feeds/3.xml,true",
          "Feed 4,https://example.com/feeds/4.xml,true",
          "Feed 5,https://example.com/feeds/5.xml,true",
          "Feed 6,not-a-url,true",
          "Feed 7,https://example.com/feeds/7.xml,true",
          "Feed 8,https://example.com/feeds/8.xml,true",
          "Feed 9,,true",
          "Feed 10,https://example.com/feeds/10.xml,true"
        )
      end

      it "counts seven successes and three errors" do
        expect(import(ten_rows_three_bad)).to have_attributes(
          total_count: 10,
          success_count: 7,
          skipped_count: 0,
          error_count: 3
        )
      end

      it "leaves the seven good feeds in the database" do
        import(ten_rows_three_bad)

        expect(Feed.count).to eq(7)
        expect(Feed.pluck(:title)).to contain_exactly("Feed 1", "Feed 2", "Feed 4", "Feed 5", "Feed 7", "Feed 8", "Feed 10")
      end

      it "does not roll the good rows back when a later row fails" do
        import(ten_rows_three_bad)

        expect(Feed.exists?(url: "https://example.com/feeds/1.xml")).to be(true)
        expect(Feed.exists?(url: "https://example.com/feeds/10.xml")).to be(true)
      end

      it "records the line number each rejection came from" do
        import(ten_rows_three_bad)

        expect(import_job.reload.error_report.map { |entry| entry["line"] }).to eq([ 4, 7, 10 ])
      end

      it "records the url each rejection came from" do
        import(ten_rows_three_bad)
        urls = import_job.reload.error_report.map { |entry| entry["url"] }

        expect(urls).to eq([ "https://example.com/feeds/3.xml", "not-a-url", nil ])
      end

      it "records the reason each rejection failed" do
        import(ten_rows_three_bad)
        messages = import_job.reload.error_report.map { |entry| entry["message"] }

        expect(messages[0]).to include("Title can't be blank")
        expect(messages[1]).to include("Url is invalid")
        expect(messages[2]).to include("Url can't be blank")
      end

      it "finishes as completed, because rejected rows are data and not a failure" do
        import(ten_rows_three_bad)

        expect(import_job.reload.status).to eq("completed")
      end

      it "rejects a row whose active column is not a boolean" do
        import(csv_with("Feed 1,https://example.com/feeds/1.xml,maybe"))

        expect(Feed.count).to eq(0)
        expect(import_job.reload.error_report.first["message"]).to include("active must be one of")
      end
    end

    context "when a url is already registered" do
      let!(:existing) { create(:feed, title: "Already here", url: "https://example.com/feeds/1.xml") }

      let(:csv) do
        csv_with(
          "Feed 1,https://example.com/feeds/1.xml,true",
          "Feed 2,https://example.com/feeds/2.xml,true"
        )
      end

      it "counts the row as a skip rather than an error" do
        expect(import(csv)).to have_attributes(
          total_count: 2,
          success_count: 1,
          skipped_count: 1,
          error_count: 0
        )
      end

      it "keeps the skip out of the error report" do
        import(csv)

        expect(import_job.reload).to have_attributes(error_count: 0, error_report: [])
      end

      it "does not overwrite the feed that was already there" do
        import(csv)

        expect(existing.reload.title).to eq("Already here")
        expect(Feed.count).to eq(2)
      end

      it "still reports a duplicated row that is also malformed as an error" do
        import(csv_with(",https://example.com/feeds/1.xml,true"))

        expect(import_job.reload).to have_attributes(error_count: 1)
      end
    end

    context "when the file has a header and no rows" do
      it "completes without creating anything" do
        expect(import("title,url,active\n")).to have_attributes(
          total_count: 0,
          success_count: 0,
          skipped_count: 0,
          error_count: 0
        )

        expect(Feed.count).to eq(0)
        expect(import_job.reload.status).to eq("completed")
      end
    end

    context "when a row has fewer columns than the header" do
      it "rejects it like any other invalid row and keeps going" do
        result = import(csv_with("Feed with nothing else", "Feed 2,https://example.com/feeds/2.xml,true"))

        expect(result).to have_attributes(total_count: 2, success_count: 1, error_count: 1)
        expect(import_job.reload.error_report.first).to include("line" => 2, "url" => nil)
        expect(import_job.error_report.first["message"]).to include("Url can't be blank")
      end
    end

    context "when something unexpected escapes the run" do
      it "marks the import failed and re-raises" do
        allow(Feed).to receive(:new).and_raise(ActiveRecord::StatementInvalid, "connection lost")

        expect { import(csv_with("Feed 1,https://example.com/feeds/1.xml,true")) }
          .to raise_error(ActiveRecord::StatementInvalid)

        expect(import_job.reload.status).to eq("failed")
      end
    end
  end
end
