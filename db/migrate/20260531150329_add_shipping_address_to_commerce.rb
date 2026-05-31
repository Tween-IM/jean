class AddShippingAddressToCommerce < ActiveRecord::Migration[7.1]
  def change
    add_column :commerce_checkouts, :shipping_address_line1, :string
    add_column :commerce_checkouts, :shipping_address_line2, :string
    add_column :commerce_checkouts, :shipping_city, :string
    add_column :commerce_checkouts, :shipping_state, :string
    add_column :commerce_checkouts, :shipping_postal_code, :string
    add_column :commerce_checkouts, :shipping_country, :string, default: "NG"
    add_column :commerce_checkouts, :shipping_phone, :string

    add_column :commerce_orders, :shipping_address_line1, :string
    add_column :commerce_orders, :shipping_address_line2, :string
    add_column :commerce_orders, :shipping_city, :string
    add_column :commerce_orders, :shipping_state, :string
    add_column :commerce_orders, :shipping_postal_code, :string
    add_column :commerce_orders, :shipping_country, :string, default: "NG"
    add_column :commerce_orders, :shipping_phone, :string
  end
end
