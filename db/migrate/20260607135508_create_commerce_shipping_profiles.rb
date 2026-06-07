class CreateCommerceShippingProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :commerce_shipping_profiles do |t|
      t.string :shipping_profile_id, null: false
      t.references :commerce_merchant, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :processing_time_days, default: 1
      t.string :origin_warehouse_id
      t.jsonb :zones, default: [], null: false
      t.integer :free_shipping_threshold_cents
      t.string :status, default: "active", null: false

      t.timestamps
    end

    add_index :commerce_shipping_profiles, :shipping_profile_id, unique: true
    add_index :commerce_shipping_profiles, [:commerce_merchant_id, :status]
  end
end
