# Fetches one feed.
#
# One job per feed, rather than one job that walks the whole table: a single
# unreachable host then fails on its own, retries on its own, and never delays
# or re-runs the feeds that were fine.
class FetchFeedJob < ApplicationJob
  queue_as :feeds

  # Three attempts in total, spread by Active Job's polynomial backoff (a few
  # seconds, then a few tens of seconds). Feed hosts fail in bursts -- a deploy,
  # a rate limit, a blip -- and are usually back well inside that window. Past
  # three attempts the failure is not transient, and the job is more useful in
  # the dead set, where a human can see it, than retried for hours. The feed row
  # already carries last_status and last_error, so nothing is lost either way.
  retry_on FeedFetcher::Error, wait: :polynomially_longer, attempts: 3

  # The argument is the id and not the record. A serialised record is a copy of
  # the row as it looked when the job was enqueued, which by the time a worker
  # picks it up may be stale or deleted; an id forces a fresh read and makes the
  # payload in Redis small.
  def perform(feed_id)
    feed = Feed.find_by(id: feed_id)

    # The feed may have been deleted or switched off between being scheduled and
    # being executed. Neither is an error, so there is nothing to report.
    return if feed.nil? || !feed.active?

    FeedFetcher.new(feed).call
  end
end
