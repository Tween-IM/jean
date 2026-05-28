class CreateCommerceCarts < ActiveRecord::Migration[8.1]
  def change
    create_table :commerce_carts do |t|
      t.string :cart_id, null: false
      t.string :buyer_user_id, null: false
      t.references :commerce_merchant, null: false, foreign_key: true
      t.string :status, null: false, default: "active"
      t.integer :subtotal_cents, null: false, default: 0
      t.integer :tax_cents, null: false, default: 0
      t.integer :shipping_cents, null: false, default: 0
      t.integer :discount_cents, null: false, default: 0
      t.integer :total_cents, null: false, default: 0
      t.string :currency, null: false, default: "NGN"

      t.timestamps
    end

    add_index :commerce_carts, :cart_id, unique: true
    add_index :commerce_carts, [ :buyer_user_id, :status ]
  end
end
