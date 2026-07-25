require "rails_helper"

RSpec.describe ScheduleFeedFetchesJob do
  include ActiveJob::TestHelper

  it "runs on the default queue" do
    expect(described_class.new.queue_name).to eq("default")
  end

  describe "#perform" do
    it "enqueues a FetchFeedJob for each active feed" do
      first, second = create_list(:feed, 2)

      expect { described_class.perform_now }
        .to have_enqueued_job(FetchFeedJob).with(first.id).on_queue("feeds")
        .and have_enqueued_job(FetchFeedJob).with(second.id).on_queue("feeds")
    end

    it "enqueues one job per feed and no more" do
      create_list(:feed, 3)

      expect { described_class.perform_now }
        .to have_enqueued_job(FetchFeedJob).exactly(3).times
    end

    it "ignores feeds that have been switched off" do
      create(:feed, active: false)

      expect { described_class.perform_now }.not_to have_enqueued_job(FetchFeedJob)
    end

    it "fetches nothing itself" do
      create(:feed)
      allow(FeedFetcher).to receive(:new)

      described_class.perform_now

      expect(FeedFetcher).not_to have_received(:new)
    end
  end
end
