FactoryBot.define do
  factory :import_job do
    sequence(:filename) { |n| "feeds-#{n}.csv" }
    status { :pending }
    total_count { 0 }
    success_count { 0 }
    error_count { 0 }
    error_report { [] }
  end
end
