class CreatePhoneContactHashes < ActiveRecord::Migration[8.1]
  def change
    create_table :phone_contact_hashes do |t|
      t.string :user_id, null: false
      t.string :phone_hash, null: false

      t.timestamps
    end
    add_index :phone_contact_hashes, [:phone_hash, :user_id]
    add_index :phone_contact_hashes, :user_id
  end
end
