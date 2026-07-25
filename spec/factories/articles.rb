FactoryBot.define do
  factory :article do
    feed
    # guid is unique per feed, so it needs a sequence as well.
    sequence(:guid) { |n| "urn:example:article:#{n}" }
    sequence(:title) { |n| "Example Article #{n}" }
    sequence(:url) { |n| "https://example.com/articles/#{n}" }
    summary { "A short summary of the article." }
    published_at { Time.current }
  end
end
