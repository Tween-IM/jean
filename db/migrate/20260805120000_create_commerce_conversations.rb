class CreateCommerceConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :commerce_conversations do |t|
      t.string :conversation_id, null: false
      t.string :buyer_user_id, null: false
      t.string :product_id, null: false
      t.string :matrix_room_id
      t.string :status, null: false, default: "open"
      t.datetime :last_message_at

      t.timestamps
    end

    add_index :commerce_conversations, :conversation_id, unique: true
    add_index :commerce_conversations, [ :buyer_user_id, :product_id ], unique: true
    add_index :commerce_conversations, :buyer_user_id
  end
end
