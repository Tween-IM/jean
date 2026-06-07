class CreateCommerceWarehouses < ActiveRecord::Migration[8.1]
  def change
    create_table :commerce_warehouses do |t|
      t.string :warehouse_id, null: false
      t.references :commerce_merchant, null: false, foreign_key: true
      t.string :name, null: false
      t.string :address_line1
      t.string :address_line2
      t.string :city
      t.string :state
      t.string :postal_code
      t.string :country, default: "NG"
      t.string :phone
      t.boolean :is_default, default: false
      t.string :status, default: "active", null: false

      t.timestamps
    end

    add_index :commerce_warehouses, :warehouse_id, unique: true
    add_index :commerce_warehouses, [:commerce_merchant_id, :status]
  end
end
