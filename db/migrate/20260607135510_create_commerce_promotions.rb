class CreateCommercePromotions < ActiveRecord::Migration[8.1]
  def change
    create_table :commerce_promotions do |t|
      t.string :promotion_id, null: false
      t.references :commerce_merchant, null: false, foreign_key: true
      t.string :name
      t.string :type
      t.integer :budget_cents
      t.integer :spent_cents, default: 0
      t.datetime :start_at
      t.datetime :end_at
      t.string :status, default: "draft", null: false
      t.jsonb :targeting, default: {}

      t.timestamps
    end

    add_index :commerce_promotions, :promotion_id, unique: true
    add_index :commerce_promotions, [:commerce_merchant_id, :status]
  end
end
