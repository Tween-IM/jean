class CreateSocialChats < ActiveRecord::Migration[8.1]
  def change
    create_table :social_chats do |t|
      t.string :user_a_id, null: false
      t.string :user_b_id, null: false
      t.string :matrix_room_id
      t.string :status, default: 'active', null: false
      t.string :blocked_by_user_id
      t.datetime :last_message_at

      t.timestamps
    end
    add_index :social_chats, [:user_a_id, :user_b_id], unique: true
    add_index :social_chats, :matrix_room_id, unique: true
    add_index :social_chats, :user_a_id
    add_index :social_chats, :user_b_id
  end
end
