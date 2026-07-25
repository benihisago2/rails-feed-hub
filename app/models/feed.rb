# A registered RSS/Atom source. Fetching itself lives in a service object; this
# class only describes the structure and the rules the data has to satisfy.
class Feed < ApplicationRecord
  # Result of the most recent fetch attempt.
  #
  # Backed by a string column rather than an integer: an operator reading the
  # table during an incident sees "failed", not "2", and inserting a new value
  # into the middle of the list later cannot silently reassign existing rows.
  #
  # No prefix is needed. The generated scopes are pending / ok / failed (plus
  # their not_* counterparts); none of them collides with the `active` scope
  # below, which comes from the boolean column of the same name.
  enum :last_status, { pending: "pending", ok: "ok", failed: "failed" }

  has_many :articles, dependent: :destroy

  validates :title, presence: true
  validates :url, presence: true, uniqueness: true, format: { with: URL_FORMAT, allow_blank: true }
  validates :last_status, presence: true

  # The scheduled fetch only ever looks at feeds the user has left enabled.
  scope :active, -> { where(active: true) }
end
