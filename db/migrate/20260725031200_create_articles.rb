# Articles are the entries harvested from a feed.
class CreateArticles < ActiveRecord::Migration[8.0]
  def change
    create_table :articles do |t|
      # index: false on purpose -- the composite unique index added below has
      # feed_id as its leading column, so it already serves feed lookups and
      # the foreign key. A separate single column index would be dead weight.
      t.references :feed, null: false, foreign_key: true, index: false
      t.string :guid, null: false
      t.string :title, null: false
      t.string :url, null: false
      t.text :summary
      t.datetime :published_at

      t.timestamps
    end

    # The deduplication rule of the whole application, expressed as a database
    # constraint rather than an application level existence check.
    #
    # A guid is only unique within its own feed, so the pair (feed_id, guid) is
    # the real identity of an article. Fetches run concurrently in Sidekiq, and
    # a check-then-insert in Ruby has a window between the SELECT and the
    # INSERT. Only the index closes that window.
    add_index :articles, [ :feed_id, :guid ], unique: true

    # The article list is always ordered newest first. A descending index lets
    # PostgreSQL walk the index in the order the query asks for, with no sort
    # step, and it is also what pagination will read later.
    add_index :articles, :published_at, order: { published_at: :desc }
  end
end
