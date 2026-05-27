class CreateCommerceSkus < ActiveRecord::Migration[8.1]
  def change
    create_table :commerce_skus do |t|
      t.references :commerce_product, null: false, foreign_key: true
      t.string :sku_id, null: false
      t.string :title
      t.integer :price_cents, null: false
      t.string :currency, null: false
      t.string :inventory_status, null: false, default: "in_stock"
      t.integer :quantity_available
      t.json :properties, null: false, default: {}

      t.timestamps
    end

    add_index :commerce_skus, :sku_id, unique: true
    add_index :commerce_skus, [ :commerce_product_id, :inventory_status ]
  end
end
