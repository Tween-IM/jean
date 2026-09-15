# frozen_string_literal: true

# Storefronts can be imported from external marketplaces too (a Jumia/Konga
# seller or brand page becomes a real store). This records where the store
# came from and any contact details the source published, so the platform
# team can reach the seller out-of-band.
#
# `contact_*` is operator data, not public storefront data — it is only
# serialised for the merchant owner.
class AddStorefrontImportProvenance < ActiveRecord::Migration[8.1]
  def change
    change_table :commerce_storefronts, bulk: true do |t|
      t.string :source_platform
      t.string :source_kind # "seller" | "brand"
      t.string :source_id
      t.text :source_url
      t.jsonb :source_payload, default: {}, null: false
      t.datetime :source_synced_at

      t.string :contact_phone
      t.string :contact_email
      t.string :contact_website
      t.text :contact_address
      t.jsonb :social_links, default: {}, null: false
    end

    add_index :commerce_storefronts, [ :source_platform, :source_kind, :source_id ],
      name: "index_commerce_storefronts_on_source_identity"
  end
end
