FactoryBot.define do
  factory :feed do
    # Sequences on the unique columns so several feeds can coexist in one
    # example without tripping the unique index on url.
    sequence(:title) { |n| "Example Feed #{n}" }
    sequence(:url) { |n| "https://example.com/feeds/#{n}.xml" }
    active { true }
    last_status { :pending }
  end
end
