class AddDmToCommerceConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :commerce_conversations, :dm_room_id, :string
    add_column :commerce_conversations, :dm_offered_by, :string
  end
end
