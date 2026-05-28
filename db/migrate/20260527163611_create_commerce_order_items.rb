class CreateCommerceOrderItems < ActiveRecord::Migration[8.1]
  def change
    create_table :commerce_order_items do |t|
      t.references :commerce_order, null: false, foreign_key: true
      t.string :sku_id, null: false
      t.string :product_id, null: false
      t.string :title, null: false
      t.integer :quantity, null: false
      t.integer :unit_price_cents, null: false
      t.integer :line_total_cents, null: false
      t.string :currency, null: false

      t.timestamps
    end
  end
end
