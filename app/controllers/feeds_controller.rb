# Registering feeds, editing them, and asking for one to be fetched by hand.
class FeedsController < ApplicationController
  def index
    # Ordered by title rather than by id so the list does not reshuffle itself
    # every time a feed is added. No association is touched by the table, so
    # there is nothing here to preload.
    @feeds = Feed.order(:title)
  end

  def new
    @feed = Feed.new
  end

  def create
    @feed = Feed.new(feed_params)

    if @feed.save
      redirect_to feeds_path, notice: "Feed created."
    else
      # 422 rather than 200: Turbo only replaces the page for a form submission
      # that answers with an error status, so a plain 200 here would leave the
      # operator looking at the old form with none of the messages.
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @feed = Feed.find(params[:id])
  end

  def update
    @feed = Feed.find(params[:id])

    if @feed.update(feed_params)
      redirect_to feeds_path, notice: "Feed updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Enqueues a fetch and returns immediately. The action deliberately does not
  # run FeedFetcher inline: a slow or unreachable publisher would otherwise hold
  # a request thread for as long as its own timeout, and the operator would sit
  # on a spinner waiting for somebody else's server. Handing it to Sidekiq also
  # means this button and the scheduled fetch take exactly the same path, with
  # the same retries.
  def fetch
    feed = Feed.find(params[:id])

    FetchFeedJob.perform_later(feed.id)

    redirect_to feeds_path, notice: "Fetch queued for #{feed.title}."
  end

  private

  # last_status, last_fetched_at and last_error are written by the fetcher and
  # are not the operator's to set, so they are not permitted here.
  def feed_params
    params.require(:feed).permit(:title, :url, :active)
  end
end
