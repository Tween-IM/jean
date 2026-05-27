class CreateCommerceOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :commerce_orders do |t|
      t.string :order_id, null: false
      t.references :commerce_merchant, null: false, foreign_key: true
      t.string :buyer_user_id, null: false
      t.string :payment_id, null: false
      t.string :status, null: false, default: "pending_payment"
      t.string :fulfillment_status, null: false, default: "unfulfilled"
      t.integer :subtotal_cents, null: false, default: 0
      t.integer :tax_cents, null: false, default: 0
      t.integer :shipping_cents, null: false, default: 0
      t.integer :discount_cents, null: false, default: 0
      t.integer :total_cents, null: false, default: 0
      t.string :currency, null: false, default: "NGN"
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :commerce_orders, :order_id, unique: true
    add_index :commerce_orders, :payment_id
    add_index :commerce_orders, [ :buyer_user_id, :status ]
  end
end
