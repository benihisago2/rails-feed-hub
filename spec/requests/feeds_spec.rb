require "rails_helper"

RSpec.describe "Feeds" do
  describe "GET /feeds" do
    it "lists the registered feeds with their last fetch result" do
      create(:feed, title: "Rails Blog", url: "https://rubyonrails.org/feed.xml",
                    last_status: :ok, last_fetched_at: Time.zone.local(2026, 7, 20, 9, 30))

      get feeds_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Rails Blog")
      expect(response.body).to include("https://rubyonrails.org/feed.xml")
      expect(response.body).to include("2026-07-20 09:30")
    end
  end

  describe "GET /feeds/new" do
    it "renders an empty form" do
      get new_feed_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("feed_title", "feed_url", "feed_active")
    end
  end

  describe "POST /feeds" do
    it "registers the feed and returns to the index" do
      expect do
        post feeds_path, params: {
          feed: { title: "Rails Blog", url: "https://rubyonrails.org/feed.xml", active: "1" }
        }
      end.to change(Feed, :count).by(1)

      expect(response).to redirect_to(feeds_path)
      expect(Feed.last).to have_attributes(title: "Rails Blog", active: true, last_status: "pending")
    end
  end

  describe "GET /feeds/:id/edit" do
    it "renders the form filled in with the feed" do
      feed = create(:feed, title: "Rails Blog")

      get edit_feed_path(feed)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Rails Blog")
    end
  end

  describe "PATCH /feeds/:id" do
    it "saves the change and returns to the index" do
      feed = create(:feed, active: true)

      patch feed_path(feed), params: { feed: { active: "0" } }

      expect(response).to redirect_to(feeds_path)
      expect(feed.reload.active).to be(false)
    end
  end

  describe "POST /feeds/:id/fetch" do
    it "enqueues a fetch for that feed and returns to the index" do
      feed = create(:feed)

      # The request only enqueues. Nothing is fetched inline, so the response
      # does not depend on the publisher being reachable.
      expect { post fetch_feed_path(feed) }
        .to have_enqueued_job(FetchFeedJob).with(feed.id).on_queue("feeds")

      expect(response).to redirect_to(feeds_path)
      expect(flash[:notice]).to include(feed.title)
    end
  end
end
