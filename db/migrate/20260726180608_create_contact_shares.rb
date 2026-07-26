class CreateContactShares < ActiveRecord::Migration[8.1]
  def change
    create_table :contact_shares do |t|
      t.string :from_user_id, null: false
      t.string :to_user_id, null: false

      t.timestamps
    end
    add_index :contact_shares, [:from_user_id, :to_user_id], unique: true
    add_index :contact_shares, :to_user_id
  end
end
