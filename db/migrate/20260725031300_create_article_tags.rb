# Join table between articles and tags.
class CreateArticleTags < ActiveRecord::Migration[8.0]
  def change
    create_table :article_tags do |t|
      # index: false -- covered by the leading column of the composite index.
      t.references :article, null: false, foreign_key: true, index: false
      # Kept indexed: the reverse lookup (all articles carrying a tag) cannot
      # use the composite index, whose leading column is article_id.
      t.references :tag, null: false, foreign_key: true

      t.timestamps
    end

    # A tag is either on an article or it is not; the same pair must never be
    # stored twice. Enforced in the database so that a double submit or a
    # retried job cannot create a duplicate row.
    add_index :article_tags, [ :article_id, :tag_id ], unique: true
  end
end
