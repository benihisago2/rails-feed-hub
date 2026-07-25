# Reads the sample feed documents in spec/fixtures/feeds.
#
# They are kept as real files rather than heredocs so that the specs read like
# the feeds they describe, and so a sample can be pasted straight out of a real
# publisher's output when a new parsing case turns up.
module FeedFixtures
  def feed_fixture(name)
    Rails.root.join("spec", "fixtures", "feeds", name).read
  end
end

RSpec.configure do |config|
  config.include FeedFixtures
end
