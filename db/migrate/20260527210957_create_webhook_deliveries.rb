class CreateWebhookDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_deliveries do |t|
      t.string :event_id, null: false
      t.string :event_type, null: false
      t.string :webhook_url, null: false
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.datetime :next_attempt_at
      t.datetime :delivered_at
      t.text :last_error
      t.integer :response_status
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end

    add_index :webhook_deliveries, :event_id, unique: true
    add_index :webhook_deliveries, [ :status, :next_attempt_at ]
    add_index :webhook_deliveries, :event_type
  end
end
