class CreateCommerceProductShipping < ActiveRecord::Migration[8.1]
  def change
    create_table :commerce_product_shipping do |t|
      t.references :commerce_product, null: false, foreign_key: true
      t.references :commerce_shipping_profile, null: false, foreign_key: true

      t.timestamps
    end

    add_index :commerce_product_shipping, [:commerce_product_id, :commerce_shipping_profile_id], unique: true, name: "index_product_shipping_on_product_and_profile"
  end
end
