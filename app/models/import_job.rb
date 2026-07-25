# Bookkeeping for one bulk CSV import of feeds. The import itself runs in a
# background job added in a later phase; this class only holds its state.
class ImportJob < ApplicationRecord
  # Same reasoning as Feed#last_status: a string column keeps the table
  # self-describing in psql and makes adding a state later a non-event.
  enum :status, { pending: "pending", running: "running", completed: "completed", failed: "failed" }

  validates :filename, presence: true
  validates :status, presence: true
  validates :total_count, :success_count, :error_count,
            numericality: { greater_than_or_equal_to: 0 }
end
