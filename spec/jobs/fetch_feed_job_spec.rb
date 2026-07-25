require "rails_helper"

RSpec.describe FetchFeedJob do
  include ActiveJob::TestHelper

  let(:feed) { create(:feed) }

  it "runs on the feeds queue" do
    expect(described_class.new.queue_name).to eq("feeds")
  end

  describe "enqueueing" do
    it "carries the feed id rather than the record" do
      expect { described_class.perform_later(feed.id) }
        .to have_enqueued_job(described_class).with(feed.id).on_queue("feeds")
    end
  end

  describe "#perform" do
    it "hands the feed to FeedFetcher" do
      fetcher = instance_double(FeedFetcher, call: nil)
      allow(FeedFetcher).to receive(:new).with(feed).and_return(fetcher)

      described_class.perform_now(feed.id)

      expect(fetcher).to have_received(:call)
    end

    it "does nothing when the feed no longer exists" do
      allow(FeedFetcher).to receive(:new)
      missing_id = Feed.maximum(:id).to_i + 1

      described_class.perform_now(missing_id)

      expect(FeedFetcher).not_to have_received(:new)
    end

    it "does nothing when the feed has been switched off" do
      inactive = create(:feed, active: false)
      allow(FeedFetcher).to receive(:new)

      described_class.perform_now(inactive.id)

      expect(FeedFetcher).not_to have_received(:new)
    end
  end

  describe "retrying" do
    it "re-enqueues itself when the fetch fails" do
      allow(FeedFetcher).to receive(:new).and_raise(FeedFetcher::TimeoutError)

      expect { described_class.perform_now(feed.id) }
        .to have_enqueued_job(described_class).with(feed.id)
    end
  end
end
