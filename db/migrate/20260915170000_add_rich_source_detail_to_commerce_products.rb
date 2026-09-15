# frozen_string_literal: true

# Every field a sales marketplace publishes about a listing, on the listing.
#
# The first import cut carried the title, the price and the gallery. Konga and
# Jumia publish far more than that — the seller's own record, stock counters,
# warranty terms, the grouped spec sheet, delivery and return terms, variant
# axes, and the marketplace's own category identity — and a storefront that
# cannot hold it cannot render it. These columns keep the imported detail
# queryable instead of burying it in `source_payload`.
class AddRichSourceDetailToCommerceProducts < ActiveRecord::Migration[8.1]
  def change
    change_table :commerce_products, bulk: true do |t|
      #: The source's own blurb; a card needs one or two sentences.
      t.text :short_description
      #: The spec sheet flat and grouped, as the source ordered it.
      t.jsonb :specifications, default: {}, null: false
      #: Warranty terms as published.
      t.jsonb :warranty, default: {}, null: false
      #: Stock counters beyond a boolean (on hand, sold, sale limits).
      t.jsonb :stock, default: {}, null: false
      #: Delivery and return terms the listing advertises.
      t.jsonb :shipping, default: {}, null: false
      #: The listing's own identifiers (source SKU, MPN, vendor url key).
      t.jsonb :identifiers, default: {}, null: false
      #: Variant axes and their options for a configurable listing.
      t.jsonb :variants, default: {}, null: false
      #: Short merchandising labels (Official Store, Free Shipping, ...).
      t.string :badges, array: true, default: [], null: false
      #: The source taxonomy chain, kept for provenance and re-mapping.
      t.string :source_category_path, array: true, default: [], null: false
    end

    add_column :commerce_skus, :image_url, :string
  end
end
