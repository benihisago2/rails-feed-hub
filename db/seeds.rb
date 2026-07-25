# Seed data for development.
#
# Three real Japanese engineering blogs, so a freshly created database has
# something meaningful to fetch instead of placeholder URLs that 404.
#
# Idempotent by design: the feed URL is the natural key, so running
# `bin/rails db:seed` twice creates nothing twice and raises nothing. The block
# form of find_or_create_by! only runs for a record that does not exist yet,
# which also means a title edited by hand is not overwritten on the next run.

seed_feeds = [
  { title: "Cookpad Tech Life", url: "https://techlife.cookpad.com/feed" },
  { title: "Cybozu Inside Out", url: "https://blog.cybozu.io/feed" },
  { title: "DevelopersIO", url: "https://dev.classmethod.jp/feed/" }
]

seed_feeds.each do |attributes|
  Feed.find_or_create_by!(url: attributes[:url]) do |feed|
    feed.title = attributes[:title]
    feed.active = true
  end
end

puts "Seeded feeds: #{Feed.count}"
