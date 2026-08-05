class AddReadTrackingToCommerceConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :commerce_conversations, :buyer_last_read_at, :datetime
    add_column :commerce_conversations, :seller_last_read_at, :datetime
  end
end
