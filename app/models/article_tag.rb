# Join model between Article and Tag.
class ArticleTag < ApplicationRecord
  belongs_to :article
  belongs_to :tag

  # Mirrors the unique index on (article_id, tag_id).
  validates :tag_id, uniqueness: { scope: :article_id }
end
