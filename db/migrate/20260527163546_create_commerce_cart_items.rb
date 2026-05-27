class CreateCommerceCartItems < ActiveRecord::Migration[8.1]
  def change
    create_table :commerce_cart_items do |t|
      t.references :commerce_cart, null: false, foreign_key: true
      t.references :commerce_sku, null: false, foreign_key: true
      t.integer :quantity, null: false
      t.integer :unit_price_cents, null: false
      t.integer :line_total_cents, null: false
      t.string :currency, null: false

      t.timestamps
    end

    add_index :commerce_cart_items, [ :commerce_cart_id, :commerce_sku_id ], unique: true, name: "index_commerce_cart_items_unique_sku"
  end
end
