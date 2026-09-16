# frozen_string_literal: true

# Who made a listing and who supplies it, as facts rather than payload.
#
# The source publishes two different parties on every listing: the brand it
# belongs to ("Nokia") and the seller that fulfils it ("Kriscrown global
# links"). Both arrived in `source_payload` and neither was queryable, so the
# catalogue could not be browsed by brand, an order could not say where the
# goods come from, and the platform's own margin was invisible.
#
# These columns are ours, not the source's:
#
#   * the storefront keeps being the shelf a listing is shown on
#   * the merchant keeps being the platform entity that sells to the buyer
#   * `supplier_*` is the party the goods must actually be bought from
#
# Order lines freeze the same facts at purchase time, because a listing's
# supplier can be re-imported later and an order has to record where *that*
# order was meant to come from.
class AddSourceSupplierIdentity < ActiveRecord::Migration[8.1]
  def change
    change_table :commerce_products, bulk: true do |t|
      # The listing's brand as the source names it.
      t.string :brand
      # The fulfilling seller: name, source id, and the marketplace it sells on.
      t.string :supplier_name
      t.string :supplier_id
      t.string :supplier_platform
      t.text :supplier_url
      # What the source charged for it when we last read the listing. Kept so
      # a sale can be costed against whatever we charge.
      t.integer :source_price_cents
    end

    add_index :commerce_products, :brand
    add_index :commerce_products, :supplier_name
    add_index :commerce_products, :supplier_id

    change_table :commerce_order_items, bulk: true do |t|
      t.string :brand
      t.string :supplier_name
      t.string :supplier_id
      t.string :supplier_platform
      t.text :supplier_url
      t.integer :source_price_cents
    end
  end
end
