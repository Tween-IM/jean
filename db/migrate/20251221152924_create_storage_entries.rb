class CreateStorageEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :storage_entries do |t|
      t.references :user, null: false, foreign_key: true
      t.string :miniapp_id
      t.string :key
      t.text :value
      t.datetime :expires_at

      t.timestamps
    end
  end
end
