class CreateCommerceCheckouts < ActiveRecord::Migration[8.1]
  def change
    create_table :commerce_checkouts do |t|
      t.string :checkout_id, null: false
      t.references :commerce_cart, null: false, foreign_key: true
      t.string :buyer_user_id, null: false
      t.references :commerce_merchant, null: false, foreign_key: true
      t.string :status, null: false, default: "created"
      t.string :payment_id
      t.string :order_id
      t.jsonb :metadata, null: false, default: {}
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :commerce_checkouts, :checkout_id, unique: true
    add_index :commerce_checkouts, :payment_id
    add_index :commerce_checkouts, [ :buyer_user_id, :status ]
  end
end
