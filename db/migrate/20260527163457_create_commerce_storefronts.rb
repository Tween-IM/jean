class CreateCommerceStorefronts < ActiveRecord::Migration[8.1]
  def change
    create_table :commerce_storefronts do |t|
      t.references :commerce_merchant, null: false, foreign_key: true
      t.string :storefront_id, null: false
      t.string :slug, null: false
      t.string :display_name, null: false
      t.text :description
      t.string :status, null: false, default: "draft"

      t.timestamps
    end

    add_index :commerce_storefronts, :storefront_id, unique: true
    add_index :commerce_storefronts, [ :commerce_merchant_id, :slug ], unique: true
  end
end
