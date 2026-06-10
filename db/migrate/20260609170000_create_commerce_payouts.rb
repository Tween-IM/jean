class CreateCommercePayouts < ActiveRecord::Migration[8.1]
  def change
    create_table :commerce_payouts do |t|
      t.string :payout_id, null: false
      t.references :commerce_merchant, null: false, foreign_key: true
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: 'NGN'
      t.string :status, null: false, default: 'pending'
      t.string :payout_method
      t.string :destination_account_number
      t.string :destination_bank_code
      t.string :destination_bank_name
      t.string :reference_id
      t.jsonb :metadata, default: {}
      t.datetime :processed_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :commerce_payouts, :payout_id, unique: true
    add_index :commerce_payouts, :reference_id, unique: true
    add_index :commerce_payouts, [:commerce_merchant_id, :status]
  end
end
