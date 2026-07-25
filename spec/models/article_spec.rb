require "rails_helper"

RSpec.describe Article do
  subject { build(:article) }

  it "has a valid factory" do
    expect(build(:article)).to be_valid
  end

  describe "associations" do
    it { is_expected.to belong_to(:feed) }
    it { is_expected.to have_many(:article_tags).dependent(:destroy) }
    it { is_expected.to have_many(:tags).through(:article_tags) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:guid) }
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:url) }
    it { is_expected.to validate_uniqueness_of(:guid).scoped_to(:feed_id) }

    it { is_expected.to allow_value("https://example.com/posts/1").for(:url) }
    it { is_expected.not_to allow_value("/posts/1").for(:url) }
  end

  describe "guid scoping" do
    it "allows the same guid on two different feeds" do
      create(:article, feed: create(:feed), guid: "shared-guid")
      other = build(:article, feed: create(:feed), guid: "shared-guid")

      expect(other).to be_valid
    end
  end

  describe ".recent" do
    it "orders articles newest first" do
      older = create(:article, published_at: 2.days.ago)
      newer = create(:article, published_at: 1.hour.ago)

      expect(described_class.recent.to_a).to eq([ newer, older ])
    end
  end

  describe "no default_scope" do
    it "returns rows in the order the caller asks for and nothing more" do
      expect(described_class.all.to_sql).not_to include("ORDER BY")
    end
  end

  describe "database constraints" do
    # The point of this example is that the guarantee lives in PostgreSQL, not
    # in Ruby. Fetch jobs run concurrently, so a "does it already exist?" check
    # followed by an insert always has a race window; the unique index does
    # not. Skipping validations is how we get past the Rails layer to reach it.
    it "rejects a duplicate (feed_id, guid) pair even when validations are skipped" do
      feed = create(:feed)
      create(:article, feed: feed, guid: "duplicate-guid")
      duplicate = build(:article, feed: feed, guid: "duplicate-guid")

      # A constraint violation aborts the transaction that rspec-rails opens
      # around the example, so no further database work may follow this line
      # inside the same example -- it would fail with PG::InFailedSqlTransaction.
      expect { duplicate.save(validate: false) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
