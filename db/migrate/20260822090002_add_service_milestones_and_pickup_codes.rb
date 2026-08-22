class AddServiceMilestonesAndPickupCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :commerce_service_milestones do |t|
      t.string :milestone_id, null: false
      t.references :commerce_order, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.bigint :amount_cents, null: false, default: 0
      t.string :currency, null: false, default: "NGN"
      t.string :status, null: false, default: "pending"
      t.datetime :scheduled_at
      t.datetime :completed_at
      t.datetime :released_at
      t.jsonb :evidence, null: false, default: []
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :commerce_service_milestones, :milestone_id, unique: true
    add_index :commerce_service_milestones, [ :commerce_order_id, :status ]

    create_table :commerce_pickup_codes do |t|
      t.string :code_hash, null: false
      t.references :commerce_fulfillment, null: false, foreign_key: true
      t.string :status, null: false, default: "active"
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.timestamps
    end

    add_index :commerce_pickup_codes, :code_hash, unique: true
    add_index :commerce_pickup_codes, [ :commerce_fulfillment_id, :status ]
  end
end
