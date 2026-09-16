# frozen_string_literal: true

# What has to be bought, from whom, and where it has got to.
#
# The platform sells the mirrored catalogue itself, so a paid order for an
# imported listing is not a request to a merchant — it is a job: someone has to
# go to the source, buy the item, receive it and deliver it. Without a record
# per line there is nothing to work from and no way to tell an operator what an
# order is waiting on.
#
# One row per order line, because one basket can draw on several sellers and
# each is its own purchase with its own cost, reference and tracking.
class CreateCommerceProcurements < ActiveRecord::Migration[8.1]
  def change
    create_table :commerce_procurements do |t|
      t.references :commerce_order, null: false, foreign_key: true
      t.references :commerce_order_item, null: false, foreign_key: true, index: { unique: true }

      # pending → ordered → received → dispatched → delivered, or cancelled/failed.
      t.string :status, null: false, default: "pending"

      # Copied from the line so the queue survives a re-import.
      t.string :supplier_name
      t.string :supplier_platform
      t.text :supplier_url

      # The order we placed at the source, and what it actually cost us.
      t.string :external_order_ref
      t.integer :cost_cents
      t.string :currency

      t.string :courier
      t.string :tracking_number
      t.text :notes
      t.string :started_by_user_id

      t.datetime :ordered_at
      t.datetime :received_at
      t.datetime :dispatched_at
      t.datetime :delivered_at

      t.timestamps
    end

    add_index :commerce_procurements, :status
    add_index :commerce_procurements, [ :status, :created_at ]
  end
end
