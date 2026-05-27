class CreateCommerceProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :commerce_products do |t|
      t.references :commerce_merchant, null: false, foreign_key: true
      t.references :commerce_storefront, foreign_key: true
      t.string :product_id, null: false
      t.string :title, null: false
      t.text :description
      t.json :media_urls, null: false, default: []
      t.string :status, null: false, default: "draft"

      t.timestamps
    end

    add_index :commerce_products, :product_id, unique: true
    add_index :commerce_products, [ :commerce_merchant_id, :status ]
  end
end
