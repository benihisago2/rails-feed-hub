# An entry harvested from a feed.
#
# There is intentionally no default_scope here. Ordering is opt-in through the
# `recent` scope, so a reader of any query can tell what it will return without
# having to remember an invisible clause bolted on by the model.
class Article < ApplicationRecord
  belongs_to :feed

  has_many :article_tags, dependent: :destroy
  has_many :tags, through: :article_tags

  # Mirrors the unique index on (feed_id, guid). The validation exists to give
  # a readable error message; the index is what actually guarantees it.
  validates :guid, presence: true, uniqueness: { scope: :feed_id }
  validates :title, presence: true
  validates :url, presence: true, format: { with: URL_FORMAT, allow_blank: true }

  # Newest first, matching the descending index on published_at.
  scope :recent, -> { order(published_at: :desc) }
end
