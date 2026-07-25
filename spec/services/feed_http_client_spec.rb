require "rails_helper"

RSpec.describe FeedHttpClient do
  subject(:client) { described_class.new }

  let(:url) { "https://example.com/blog/feed.xml" }

  describe "#call" do
    it "returns the response body as a UTF-8 string" do
      stub_request(:get, url).to_return(status: 200, body: "<rss></rss>")

      body = client.call(url)

      expect(body).to eq("<rss></rss>")
      expect(body.encoding).to eq(Encoding::UTF_8)
    end

    it "sends the feed reader user agent" do
      request = stub_request(:get, url)
        .with(headers: { "User-Agent" => "FeedHub/1.0" })
        .to_return(status: 200, body: "<rss></rss>")

      client.call(url)

      expect(request).to have_been_requested
    end

    it "raises FeedFetcher::TimeoutError when the request times out" do
      stub_request(:get, url).to_timeout

      expect { client.call(url) }.to raise_error(FeedFetcher::TimeoutError, /timed out/)
    end

    it "raises FeedFetcher::HttpError carrying the status on a non-2xx response" do
      stub_request(:get, url).to_return(status: 404, body: "Not Found")

      expect { client.call(url) }.to raise_error(FeedFetcher::HttpError) { |error|
        expect(error.status).to eq(404)
      }
    end
  end
end
