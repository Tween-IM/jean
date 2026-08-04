class AddUniqueIndexToPhoneContactHashes < ActiveRecord::Migration[8.1]
  def up
    # Deduplicate any existing rows before adding the unique index. Keep the
    # first row for each (user_id, phone_hash) pair.
    execute <<~SQL
      DELETE FROM phone_contact_hashes a
      USING phone_contact_hashes b
      WHERE a.id > b.id
        AND a.user_id = b.user_id
        AND a.phone_hash = b.phone_hash
    SQL

    remove_index :phone_contact_hashes, name: "index_phone_contact_hashes_on_phone_hash_and_user_id"
    add_index :phone_contact_hashes, [ :phone_hash, :user_id ],
      unique: true,
      name: "index_phone_contact_hashes_on_phone_hash_and_user_id"
  end

  def down
    remove_index :phone_contact_hashes, name: "index_phone_contact_hashes_on_phone_hash_and_user_id"
    add_index :phone_contact_hashes, [ :phone_hash, :user_id ],
      name: "index_phone_contact_hashes_on_phone_hash_and_user_id"
  end
end
