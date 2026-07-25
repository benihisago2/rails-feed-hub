# Bookkeeping for one bulk CSV import of feeds. The import itself runs in
# CsvImportJob; this class holds its state and the uploaded file.
class ImportJob < ApplicationRecord
  # The upload lives in Active Storage rather than in a column. The controller
  # only has to persist the bytes and hand over an id: the worker reads the file
  # back on its own machine, which is the whole reason the request can return
  # before a single row has been parsed.
  has_one_attached :file

  # Same reasoning as Feed#last_status: a string column keeps the table
  # self-describing in psql and makes adding a state later a non-event.
  enum :status, { pending: "pending", running: "running", completed: "completed", failed: "failed" }

  validates :filename, presence: true
  validates :status, presence: true
  validates :total_count, :success_count, :error_count,
            numericality: { greater_than_or_equal_to: 0 }
end
