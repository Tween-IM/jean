class CreateCommerceMerchants < ActiveRecord::Migration[8.1]
  def change
    create_table :commerce_merchants do |t|
      t.string :merchant_id, null: false
      t.string :miniapp_id, null: false
      t.string :owner_user_id
      t.string :display_name, null: false
      t.string :status, null: false, default: "pending_review"
      t.string :wallet_id, null: false
      t.string :webhook_url

      t.timestamps
    end

    add_index :commerce_merchants, :merchant_id, unique: true
    add_index :commerce_merchants, :miniapp_id
    add_index :commerce_merchants, :status
  end
end
