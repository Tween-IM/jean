class AddProtectedCommerceOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :commerce_offers do |t|
      t.string :offer_id, null: false
      t.string :conversation_id, null: false
      t.string :proposer_user_id, null: false
      t.string :recipient_user_id, null: false
      t.string :offer_type, null: false, default: "product"
      t.integer :version, null: false, default: 1
      t.string :status, null: false, default: "draft"
      t.string :currency, null: false, default: "NGN"
      t.bigint :subtotal_cents, null: false, default: 0
      t.bigint :delivery_fee_cents, null: false, default: 0
      t.bigint :buyer_fee_cents, null: false, default: 0
      t.bigint :discount_cents, null: false, default: 0
      t.bigint :total_cents, null: false, default: 0
      t.bigint :commission_cents, null: false, default: 0
      t.bigint :seller_proceeds_cents, null: false, default: 0
      t.datetime :expires_at
      t.jsonb :terms_json, null: false, default: {}
      t.string :superseded_by_offer_id
      t.string :parent_offer_id
      t.string :accepted_by_user_id
      t.datetime :accepted_at
      t.datetime :responded_at
      t.timestamps
    end

    add_index :commerce_offers, :offer_id, unique: true
    add_index :commerce_offers, [ :conversation_id, :version ]
    add_index :commerce_offers, :status
    add_index :commerce_offers, :parent_offer_id

    create_table :commerce_change_orders do |t|
      t.string :change_order_id, null: false
      t.references :commerce_order, null: false, foreign_key: true
      t.string :proposer_user_id, null: false
      t.jsonb :scope_delta, null: false, default: {}
      t.bigint :amount_delta_cents, null: false, default: 0
      t.jsonb :deadline_delta, null: false, default: {}
      t.string :status, null: false, default: "proposed"
      t.string :accepted_by_user_id
      t.datetime :accepted_at
      t.timestamps
    end

    add_index :commerce_change_orders, :change_order_id, unique: true
    add_index :commerce_change_orders, [ :commerce_order_id, :status ]

    create_table :commerce_disputes do |t|
      t.string :dispute_id, null: false
      t.references :commerce_order, null: false, foreign_key: true
      t.string :protected_payment_id
      t.string :opened_by_user_id, null: false
      t.string :reason, null: false
      t.text :description
      t.string :status, null: false, default: "open"
      t.jsonb :resolution, null: false, default: {}
      t.jsonb :snapshots, null: false, default: {}
      t.string :resolved_by_user_id
      t.datetime :opened_at, null: false
      t.datetime :resolved_at
      t.timestamps
    end

    add_index :commerce_disputes, :dispute_id, unique: true
    add_index :commerce_disputes, [ :commerce_order_id, :status ]

    create_table :commerce_dispute_evidence do |t|
      t.string :evidence_id, null: false
      t.references :commerce_dispute, null: false, foreign_key: true
      t.string :uploaded_by_user_id, null: false
      t.string :media_type, null: false
      t.string :url, null: false
      t.string :content_type
      t.bigint :size_bytes
      t.text :caption
      t.datetime :uploaded_at, null: false
      t.timestamps
    end

    add_index :commerce_dispute_evidence, :evidence_id, unique: true
    add_index :commerce_dispute_evidence, [ :commerce_dispute_id, :uploaded_at ]

    create_table :commerce_protected_payment_callbacks do |t|
      t.string :event_id, null: false
      t.string :event_type, null: false
      t.string :protected_payment_id
      t.jsonb :payload, null: false, default: {}
      t.string :status, null: false, default: "processed"
      t.datetime :processed_at
      t.timestamps
    end

    add_index :commerce_protected_payment_callbacks, :event_id, unique: true
    add_index :commerce_protected_payment_callbacks, :protected_payment_id
  end
end
