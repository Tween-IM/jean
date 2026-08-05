class AddStoreTypeToCommerce < ActiveRecord::Migration[7.2]
  def change
    add_column :commerce_storefronts, :store_type, :string, default: "marketplace", null: false
    add_column :commerce_products, :store_type, :string, default: "marketplace", null: false
  end
end
