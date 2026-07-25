# The hourly entry point: turns "fetch everything" into one FetchFeedJob per
# active feed.
#
# This job deliberately performs no fetching of its own. It exists so that the
# scheduler has a single thing to trigger, while the work itself stays split per
# feed, where it can fail and retry independently.
class ScheduleFeedFetchesJob < ApplicationJob
  queue_as :default

  def perform
    # find_each loads the feeds in batches instead of instantiating the whole
    # table at once, and only the id is selected because the id is all that is
    # handed on.
    Feed.active.select(:id).find_each do |feed|
      FetchFeedJob.perform_later(feed.id)
    end
  end
end
