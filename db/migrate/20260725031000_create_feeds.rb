# Feeds are the root of the domain: every article belongs to exactly one feed.
class CreateFeeds < ActiveRecord::Migration[8.0]
  def change
    create_table :feeds do |t|
      t.string :title, null: false
      t.string :url, null: false
      t.boolean :active, null: false, default: true
      t.datetime :last_fetched_at
      # Outcome of the most recent fetch: pending / ok / failed.
      # Stored as a string so the value is readable straight from psql.
      t.string :last_status, null: false, default: "pending"
      t.text :last_error

      t.timestamps
    end

    # The URL is the natural key of a feed. A unique index makes registering the
    # same source twice impossible even under concurrent requests, where the
    # Rails uniqueness validation alone would race.
    add_index :feeds, :url, unique: true

    # The scheduled fetch selects only active feeds. Once the table grows, an
    # index keeps that recurring query from degrading into a sequential scan.
    add_index :feeds, :active
  end
end
