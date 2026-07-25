FactoryBot.define do
  factory :tag do
    # Already lower case, so the value survives Tag#normalize_name unchanged.
    sequence(:name) { |n| "tag-#{n}" }
  end
end
