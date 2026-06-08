class AddProductFieldsToCommerceOrderItems < ActiveRecord::Migration[8.1]
  def change
    add_column :commerce_order_items, :product_name, :string
    add_column :commerce_order_items, :product_media_url, :string
    add_column :commerce_order_items, :variant_attributes, :jsonb, default: {}
  end
end
