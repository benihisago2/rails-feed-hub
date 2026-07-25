# Progress record for a bulk CSV import of feeds.
class CreateImportJobs < ActiveRecord::Migration[8.0]
  def change
    create_table :import_jobs do |t|
      t.string :filename, null: false
      # pending / running / completed / failed, stored as a string.
      t.string :status, null: false, default: "pending"
      t.integer :total_count, null: false, default: 0
      t.integer :success_count, null: false, default: 0
      t.integer :error_count, null: false, default: 0
      # One entry per rejected row. NOT NULL with an empty array default so the
      # column is never nil and callers never have to guard against it.
      t.jsonb :error_report, null: false, default: []

      t.timestamps
    end
  end
end
