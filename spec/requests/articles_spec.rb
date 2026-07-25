require "rails_helper"

RSpec.describe "Articles" do
  describe "GET /articles" do
    it "lists articles newest first with the feed they came from" do
      feed = create(:feed, title: "Rails Blog")
      create(:article, feed: feed, title: "Older post", published_at: 2.days.ago)
      create(:article, feed: feed, title: "Newer post", published_at: 1.hour.ago)

      get articles_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Rails Blog")
      expect(response.body.index("Newer post")).to be < response.body.index("Older post")
    end

    it "does not load the feed of each article one query at a time" do
      3.times do
        feed = create(:feed)
        create_list(:article, 2, feed: feed)
      end

      # bullet raises Bullet::Notification::UnoptimizedQueryError in the test
      # environment, so an N+1 on this page surfaces here as a failed request
      # rather than as a slow page nobody measures. The includes(:feed) in the
      # controller is what keeps it quiet.
      expect { get articles_path }.not_to raise_error

      expect(response).to have_http_status(:ok)
    end

    it "shows only the chosen feed's articles when filtered" do
      rails_feed = create(:feed, title: "Rails Blog")
      ruby_feed = create(:feed, title: "Ruby Weekly")
      create(:article, feed: rails_feed, title: "A Rails post")
      create(:article, feed: ruby_feed, title: "A Ruby post")

      get articles_path(feed_id: rails_feed.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("A Rails post")
      expect(response.body).not_to include("A Ruby post")
    end

    it "shows every feed's articles when no feed is chosen" do
      rails_feed = create(:feed, title: "Rails Blog")
      ruby_feed = create(:feed, title: "Ruby Weekly")
      create(:article, feed: rails_feed, title: "A Rails post")
      create(:article, feed: ruby_feed, title: "A Ruby post")

      get articles_path

      expect(response.body).to include("A Rails post", "A Ruby post")
    end
  end

  describe "GET /articles.csv" do
    it "sends the same collection as a CSV download" do
      feed = create(:feed, title: "Rails Blog")
      create(:article, feed: feed, title: "Ruby 3.4 released")

      get articles_path(format: :csv)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")
      expect(response.headers["Content-Disposition"]).to include("attachment")
      expect(response.body).to include("feed_title,title,url,published_at,tags")
      expect(response.body).to include("Rails Blog", "Ruby 3.4 released")
    end

    it "scopes the export to the same feed filter the page uses" do
      rails_feed = create(:feed, title: "Rails Blog")
      ruby_feed = create(:feed, title: "Ruby Weekly")
      create(:article, feed: rails_feed, title: "A Rails post")
      create(:article, feed: ruby_feed, title: "A Ruby post")

      get articles_path(format: :csv, feed_id: rails_feed.id)

      expect(response.body).to include("A Rails post")
      expect(response.body).not_to include("A Ruby post")
    end
  end
end
