require "rails_helper"
require "csv"

RSpec.describe ArticleCsvExporter do
  # The exporter yields lines, so every expectation below goes through a real
  # CSV parse of what it produced rather than through string matching. That is
  # the only way to catch a value that needed quoting and did not get it.
  def exported(scope = Article.all)
    CSV.parse(described_class.new(scope).call.to_a.join, headers: true)
  end

  describe "#call" do
    it "returns an enumerator, so the caller decides how much to hold at once" do
      expect(described_class.new.call).to be_a(Enumerator)
    end

    it "writes the header line first" do
      expect(described_class.new.call.first).to eq("feed_title,title,url,published_at,tags\n")
    end

    it "writes one row per article" do
      feed = create(:feed, title: "Rails Blog")
      article = create(
        :article,
        feed: feed,
        title: "What ON CONFLICT actually locks",
        url: "https://example.com/blog/postgres-upsert",
        published_at: Time.utc(2026, 7, 21, 9, 0, 0)
      )
      article.tags << create(:tag, name: "release")
      article.tags << create(:tag, name: "postgres")

      rows = exported

      expect(rows.size).to eq(1)
      expect(rows.first.to_h).to eq(
        "feed_title" => "Rails Blog",
        "title" => "What ON CONFLICT actually locks",
        "url" => "https://example.com/blog/postgres-upsert",
        "published_at" => "2026-07-21T09:00:00Z",
        "tags" => "postgres;release"
      )
    end

    it "writes published_at in ISO 8601" do
      create(:article, published_at: Time.utc(2026, 1, 2, 3, 4, 5))

      expect(exported.first["published_at"]).to eq("2026-01-02T03:04:05Z")
    end

    it "leaves published_at empty when the article has none" do
      create(:article, published_at: nil)

      expect(exported.first["published_at"]).to be_nil
    end

    it "leaves tags empty when the article has none" do
      create(:article)

      expect(exported.first["tags"]).to be_nil
    end

    it "quotes a value that contains the delimiter instead of splitting the row" do
      create(:article, title: "Sidekiq, Redis and you")

      rows = exported

      expect(rows.size).to eq(1)
      expect(rows.first["title"]).to eq("Sidekiq, Redis and you")
    end

    it "exports every article when the table spans several batches" do
      stub_const("#{described_class}::BATCH_SIZE", 2)
      create_list(:article, 5)

      expect(exported.size).to eq(5)
    end

    it "exports only the articles in the scope it was given" do
      wanted = create(:feed, title: "Wanted")
      create(:article, feed: wanted, title: "Kept")
      create(:article, title: "Dropped")

      expect(exported(wanted.articles).map { |row| row["title"] }).to eq([ "Kept" ])
    end
  end
end
