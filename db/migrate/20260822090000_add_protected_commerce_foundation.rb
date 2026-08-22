class AddProtectedCommerceFoundation < ActiveRecord::Migration[8.1]
  def change
    change_table :commerce_orders, bulk: true do |t|
      t.string :source, null: false, default: "storefront"
      t.string :protection_status, null: false, default: "not_eligible"
      t.string :fulfillment_type, null: false, default: "shipment"
      t.integer :terms_version, null: false, default: 1
      t.string :accepted_offer_id
      t.string :protected_payment_id
    end

    add_index :commerce_orders, :source
    add_index :commerce_orders, :protection_status
    add_index :commerce_orders, :protected_payment_id, unique: true,
      where: "protected_payment_id IS NOT NULL"

    create_table :commerce_fulfillments do |t|
      t.references :commerce_order, null: false, foreign_key: true
      t.string :fulfillment_id, null: false
      t.string :kind, null: false
      t.string :status, null: false, default: "unfulfilled"
      t.string :provider
      t.string :tracking_number
      t.string :tracking_url
      t.string :updated_by_user_id
      t.datetime :shipped_at
      t.datetime :delivered_at
      t.datetime :accepted_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :commerce_fulfillments, :fulfillment_id, unique: true
    add_index :commerce_fulfillments, [ :commerce_order_id, :status ]

    create_table :commerce_fulfillment_events do |t|
      t.references :commerce_fulfillment, null: false, foreign_key: true
      t.string :event_id, null: false
      t.string :event_type, null: false
      t.string :actor_user_id
      t.jsonb :data, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.timestamps
    end

    add_index :commerce_fulfillment_events, :event_id, unique: true
    add_index :commerce_fulfillment_events,
      [ :commerce_fulfillment_id, :occurred_at ],
      name: "idx_commerce_fulfillment_events_timeline"
  end
end
