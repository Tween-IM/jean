class CreateCommerceDmRooms < ActiveRecord::Migration[8.1]
  def change
    create_table :commerce_dm_rooms do |t|
      t.string :buyer_user_id, null: false
      t.string :seller_user_id, null: false
      t.string :matrix_room_id, null: false
      t.string :status, default: "active", null: false
      t.timestamps
    end

    add_index :commerce_dm_rooms, %i[buyer_user_id seller_user_id], unique: true, name: "index_commerce_dm_rooms_on_buyer_and_seller"
    add_index :commerce_dm_rooms, :matrix_room_id, unique: true
    add_index :commerce_dm_rooms, :seller_user_id
  end
end
