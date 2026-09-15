# frozen_string_literal: true

# Adds provenance tracking so products and reviews can be imported from
# external marketplaces (Jumia, Konga, ...) and kept in sync afterwards.
#
# `source_platform` + `source_id` / `source_review_id` form the natural key
# used to upsert on re-import, so the same source record never duplicates.
class AddCommerceImportProvenance < ActiveRecord::Migration[8.1]
  def change
    change_table :commerce_products, bulk: true do |t|
      t.string :source_platform
      t.string :source_id
      t.text :source_url
      t.jsonb :source_payload, default: {}, null: false
      t.datetime :source_synced_at
    end

    add_index :commerce_products, [ :source_platform, :source_id ],
      unique: true,
      where: "source_platform IS NOT NULL AND source_id IS NOT NULL",
      name: "index_commerce_products_on_source_identity"

    change_table :commerce_reviews, bulk: true do |t|
      t.string :source_platform
      t.string :source_review_id
      t.string :reviewer_display_name
      t.string :reviewer_handle
      t.boolean :is_anonymous, default: false, null: false
      t.boolean :imported, default: false, null: false
      t.datetime :review_date
      t.jsonb :source_payload, default: {}, null: false
    end

    add_index :commerce_reviews, [ :source_platform, :source_review_id ],
      unique: true,
      where: "source_platform IS NOT NULL AND source_review_id IS NOT NULL",
      name: "index_commerce_reviews_on_source_identity"
  end
end
