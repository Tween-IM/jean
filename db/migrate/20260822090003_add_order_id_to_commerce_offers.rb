class AddOrderIdToCommerceOffers < ActiveRecord::Migration[8.1]
  def change
    add_column :commerce_offers, :order_id, :string
    add_index :commerce_offers, :order_id
  end
end
