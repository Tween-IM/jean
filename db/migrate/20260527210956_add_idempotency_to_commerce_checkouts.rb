class AddIdempotencyToCommerceCheckouts < ActiveRecord::Migration[8.1]
  def change
    add_column :commerce_checkouts, :idempotency_key, :string
    add_index :commerce_checkouts, [ :buyer_user_id, :idempotency_key ], unique: true, where: "idempotency_key IS NOT NULL"
  end
end
