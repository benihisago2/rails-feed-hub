# A free-form label attached to articles.
class Tag < ApplicationRecord
  has_many :article_tags, dependent: :destroy
  has_many :articles, through: :article_tags

  # Normalisation runs before validation, not before save, so the uniqueness
  # validation and the unique index both see the same canonical value.
  # Without this, "Rails", "rails " and "rails" would become three rows.
  before_validation :normalize_name

  validates :name, presence: true, uniqueness: true

  private

  def normalize_name
    self.name = name.strip.downcase if name.is_a?(String)
  end
end
