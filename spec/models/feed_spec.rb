require "rails_helper"

RSpec.describe Feed do
  subject { build(:feed) }

  it "has a valid factory" do
    expect(build(:feed)).to be_valid
  end

  describe "associations" do
    it { is_expected.to have_many(:articles).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:url) }
    it { is_expected.to validate_presence_of(:last_status) }
    it { is_expected.to validate_uniqueness_of(:url) }

    it { is_expected.to allow_value("https://example.com/feed.xml").for(:url) }
    it { is_expected.to allow_value("http://example.com/feed.xml").for(:url) }
    it { is_expected.not_to allow_value("example.com/feed.xml").for(:url) }
    it { is_expected.not_to allow_value("ftp://example.com/feed.xml").for(:url) }
  end

  describe "last_status" do
    it do
      is_expected.to define_enum_for(:last_status)
        .with_values(pending: "pending", ok: "ok", failed: "failed")
        .backed_by_column_of_type(:string)
    end

    it "defaults to pending" do
      expect(described_class.new.last_status).to eq("pending")
    end
  end

  describe "defaults" do
    it "is active" do
      expect(described_class.new.active).to be(true)
    end
  end

  describe ".active" do
    it "returns only the feeds that are still enabled" do
      enabled = create(:feed, active: true)
      create(:feed, active: false)

      expect(described_class.active).to contain_exactly(enabled)
    end
  end

  describe "database constraints" do
    it "rejects a second feed with the same url" do
      create(:feed, url: "https://example.com/shared.xml")
      duplicate = build(:feed, url: "https://example.com/shared.xml")

      # save(validate: false) skips the Rails uniqueness validation on purpose:
      # what is under test here is the unique index, not the validator.
      #
      # PostgreSQL aborts the surrounding transaction when a constraint fires,
      # and rspec-rails wraps every example in one, so this has to be the last
      # database statement in the example.
      expect { duplicate.save(validate: false) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
