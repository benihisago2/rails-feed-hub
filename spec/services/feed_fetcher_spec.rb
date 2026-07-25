require "rails_helper"

RSpec.describe FeedFetcher do
  subject(:fetcher) { described_class.new(feed) }

  let(:feed) { create(:feed, url: "https://example.com/blog/feed.xml") }

  def stub_feed(body:, status: 200, content_type: "application/rss+xml")
    stub_request(:get, feed.url)
      .to_return(status: status, body: body, headers: { "Content-Type" => content_type })
  end

  describe "#call" do
    context "with an injected HTTP client" do
      # The whole point of the extraction: the parse/store path runs against a
      # canned body with no network stub at all, because the transport is a
      # collaborator the fetcher is handed rather than something built inside it.
      it "parses and stores the body the client returns without touching the network" do
        client = instance_double(FeedHttpClient, call: feed_fixture("sample_rss.xml"))

        result = described_class.new(feed, http_client: client).call

        expect(result.created_count).to eq(3)
        expect(feed.articles.count).to eq(3)
        expect(client).to have_received(:call).with(feed.url)
      end
    end

    context "with an RSS 2.0 document" do
      before { stub_feed(body: feed_fixture("sample_rss.xml")) }

      it "creates one article per entry" do
        expect { fetcher.call }.to change { feed.articles.count }.from(0).to(3)
      end

      it "reports how many articles it created" do
        result = fetcher.call

        expect(result).to have_attributes(feed_id: feed.id, entry_count: 3, created_count: 3)
      end

      it "copies the fields of an entry onto the article" do
        fetcher.call
        article = feed.articles.find_by(guid: "https://example.com/blog/postgres-upsert")

        expect(article).to have_attributes(
          title: "What ON CONFLICT actually locks",
          url: "https://example.com/blog/postgres-upsert"
        )
        expect(article.summary).to include("row locks PostgreSQL takes")
      end

      it "stores the publication date of an entry" do
        fetcher.call
        article = feed.articles.find_by(guid: "https://example.com/blog/postgres-upsert")

        expect(article.published_at).to eq(Time.utc(2025, 7, 21, 9, 0, 0))
      end

      it "keeps the guid the feed published" do
        fetcher.call

        expect(feed.articles.pluck(:guid)).to include("urn:example:blog:duplicate-articles")
      end

      it "marks the feed as fetched" do
        fetcher.call

        expect(feed.reload.last_status).to eq("ok")
        expect(feed.last_fetched_at).to be_within(5.seconds).of(Time.current)
      end

      it "clears the error left by an earlier failure" do
        feed.update!(last_status: :failed, last_error: "Connection reset by peer")

        fetcher.call

        expect(feed.reload.last_error).to be_nil
      end
    end

    context "with an Atom document" do
      before { stub_feed(body: feed_fixture("sample_atom.xml"), content_type: "application/atom+xml") }

      it "creates one article per entry" do
        expect { fetcher.call }.to change { feed.articles.count }.from(0).to(2)
      end

      it "uses the entry id as the guid and the alternate link as the url" do
        fetcher.call
        article = feed.articles.find_by(guid: "urn:uuid:8c0b6a41-2f19-4d63-b0a8-77c9e4d21b55")

        expect(article).to have_attributes(
          title: "Scheduled maintenance on 1 August",
          url: "https://example.com/updates/maintenance-2025-08-01"
        )
      end

      it "stores the publication date of an entry" do
        fetcher.call
        article = feed.articles.find_by(guid: "urn:uuid:8c0b6a41-2f19-4d63-b0a8-77c9e4d21b55")

        expect(article.published_at).to eq(Time.utc(2025, 7, 22, 14, 0, 0))
      end

      it "marks the feed as fetched" do
        fetcher.call

        expect(feed.reload.last_status).to eq("ok")
      end
    end

    context "when the same feed is fetched twice" do
      before { stub_feed(body: feed_fixture("sample_rss.xml")) }

      it "does not create the entries a second time" do
        fetcher.call

        expect { described_class.new(feed).call }.not_to change { feed.articles.count }
      end

      it "reports that nothing new was created" do
        fetcher.call

        expect(described_class.new(feed).call.created_count).to eq(0)
      end

      it "leaves the created_at of an existing article alone" do
        fetcher.call
        article = feed.articles.first
        first_seen_at = article.created_at

        described_class.new(feed).call

        expect(article.reload.created_at).to eq(first_seen_at)
      end
    end

    context "when the request times out" do
      before { stub_request(:get, feed.url).to_timeout }

      it "raises instead of reporting a successful fetch" do
        expect { fetcher.call }.to raise_error(FeedFetcher::TimeoutError, /timed out/)
      end

      it "records the failure on the feed" do
        expect { fetcher.call }.to raise_error(FeedFetcher::TimeoutError)

        expect(feed.reload.last_status).to eq("failed")
        expect(feed.last_error).to include("TimeoutError")
      end

      it "creates no articles" do
        expect { fetcher.call }.to raise_error(FeedFetcher::TimeoutError)

        expect(Article.count).to eq(0)
      end
    end

    context "when the feed responds 404" do
      before { stub_feed(body: "Not Found", status: 404) }

      it "raises with the status in the message" do
        expect { fetcher.call }.to raise_error(FeedFetcher::HttpError, /404/)
      end

      it "exposes the status on the error" do
        expect { fetcher.call }.to raise_error(FeedFetcher::HttpError) { |error|
          expect(error.status).to eq(404)
        }
      end

      it "records the failure on the feed" do
        expect { fetcher.call }.to raise_error(FeedFetcher::HttpError)

        expect(feed.reload.last_status).to eq("failed")
        expect(feed.last_error).to include("404")
      end
    end

    context "when the feed responds 500" do
      before { stub_feed(body: "Internal Server Error", status: 500) }

      it "raises with the status in the message" do
        expect { fetcher.call }.to raise_error(FeedFetcher::HttpError, /500/)
      end

      it "records the failure on the feed" do
        expect { fetcher.call }.to raise_error(FeedFetcher::HttpError)

        expect(feed.reload.last_status).to eq("failed")
      end

      it "creates no articles" do
        expect { fetcher.call }.to raise_error(FeedFetcher::HttpError)

        expect(Article.count).to eq(0)
      end
    end

    context "when the body is not well formed XML" do
      before { stub_feed(body: '<rss version="2.0"><channel><title>Half a document') }

      it "raises a parse error" do
        expect { fetcher.call }.to raise_error(FeedFetcher::ParseError)
      end

      it "records the failure on the feed" do
        expect { fetcher.call }.to raise_error(FeedFetcher::ParseError)

        expect(feed.reload.last_status).to eq("failed")
        expect(feed.last_error).to include("ParseError")
      end

      it "creates no articles" do
        expect { fetcher.call }.to raise_error(FeedFetcher::ParseError)

        expect(Article.count).to eq(0)
      end
    end

    context "when the body is XML but not a feed" do
      before { stub_feed(body: '<?xml version="1.0"?><catalog><book id="1"/></catalog>') }

      it "raises a parse error" do
        expect { fetcher.call }.to raise_error(FeedFetcher::ParseError)
      end

      it "records the failure on the feed" do
        expect { fetcher.call }.to raise_error(FeedFetcher::ParseError)

        expect(feed.reload.last_status).to eq("failed")
      end
    end

    context "when an entry is missing something the articles table requires" do
      before do
        stub_feed(body: <<~XML)
          <?xml version="1.0" encoding="UTF-8"?>
          <rss version="2.0">
            <channel>
              <title>Sparse Feed</title>
              <link>https://example.com/sparse</link>
              <description>One usable entry, one with nowhere to point the reader.</description>
              <item>
                <title>Usable</title>
                <link>https://example.com/sparse/1</link>
                <description>Has everything an article row needs.</description>
                <guid isPermaLink="true">https://example.com/sparse/1</guid>
              </item>
              <item>
                <title>No link at all</title>
                <description>The url column is NOT NULL, so this one cannot be stored.</description>
                <guid isPermaLink="false">urn:example:sparse:2</guid>
              </item>
            </channel>
          </rss>
        XML
      end

      it "stores the usable entry and skips the other" do
        expect { fetcher.call }.to change { feed.articles.count }.from(0).to(1)
      end

      it "still counts every entry it saw" do
        result = fetcher.call

        expect(result).to have_attributes(entry_count: 2, created_count: 1)
      end

      it "marks the feed as fetched" do
        fetcher.call

        expect(feed.reload.last_status).to eq("ok")
      end
    end
  end
end
