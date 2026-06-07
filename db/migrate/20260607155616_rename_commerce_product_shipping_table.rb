class RenameCommerceProductShippingTable < ActiveRecord::Migration[8.1]
  def change
    rename_table :commerce_product_shipping, :commerce_product_shippings
    rename_index :commerce_product_shippings, "index_product_shipping_on_product_and_profile", "index_product_shippings_on_product_and_profile"
  end
end
