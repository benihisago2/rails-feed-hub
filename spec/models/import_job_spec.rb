require "rails_helper"

RSpec.describe ImportJob do
  subject { build(:import_job) }

  it "has a valid factory" do
    expect(build(:import_job)).to be_valid
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:filename) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_numericality_of(:total_count).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:success_count).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:error_count).is_greater_than_or_equal_to(0) }
  end

  describe "status" do
    subject(:import_job) { described_class.new }

    it "is a string-backed enum of pending, running, completed and failed" do
      expect(import_job).to define_enum_for(:status)
        .with_values(pending: "pending", running: "running", completed: "completed", failed: "failed")
        .backed_by_column_of_type(:string)
    end

    it "defaults to pending" do
      expect(described_class.new.status).to eq("pending")
    end
  end

  describe "error_report" do
    it "defaults to an empty array rather than nil" do
      expect(described_class.new.error_report).to eq([])
    end

    it "round-trips an array of hashes through jsonb" do
      report = [ { "line" => 2, "message" => "url is invalid" } ]
      job = create(:import_job, error_report: report)

      expect(job.reload.error_report).to eq(report)
    end
  end
end
