# Tags are a flat vocabulary shared across every feed.
class CreateTags < ActiveRecord::Migration[8.0]
  def change
    create_table :tags do |t|
      t.string :name, null: false

      t.timestamps
    end

    # Names are normalised (stripped and downcased) before validation, so this
    # unique index is what actually guarantees one row per vocabulary entry.
    add_index :tags, :name, unique: true
  end
end
