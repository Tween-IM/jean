# frozen_string_literal: true

namespace :commerce do
  desc "Create (or report) the platform-owned merchant that owns imported catalogs"
  # Usage: bin/rails commerce:system_merchant
  task system_merchant: :environment do
    merchant = CommerceMerchant.system_merchant

    puts "merchant_id:  #{merchant.merchant_id}"
    puts "display_name: #{merchant.display_name}"
    puts "status:       #{merchant.status}"
    puts "wallet_id:    #{merchant.wallet_id}"
    puts "storefronts:  #{merchant.commerce_storefronts.count} (#{merchant.commerce_storefronts.imported.count} imported)"
    puts "products:     #{merchant.commerce_products.count} (#{merchant.commerce_products.imported.count} imported)"
  end

  desc "File imported listings under the categories their source published"
  # Usage: bin/rails commerce:resolve_categories [BATCH=500]
  #
  # A listing whose category never resolved sits outside our taxonomy, which
  # makes it invisible to every category browse even though the source's own
  # chain was imported alongside it. This re-runs the resolution the import
  # runs, over listings that are missing it, and is safe to run twice.
  task resolve_categories: :environment do
    batch = (ENV["BATCH"] || 500).to_i
    scope = CommerceProduct.imported.where(category_id: nil)
    puts "listings with no category: #{scope.count}"

    resolved = 0
    skipped = 0
    last_id = 0
    loop do
      products = scope.where("commerce_products.id > ?", last_id).order(:id).limit(batch).to_a
      break if products.empty?

      last_id = products.last.id
      products.each do |product|
        if Commerce::CategoryResolver.apply_to(product, Array(product.source_category_path))
          product.save!
          resolved += 1
        else
          skipped += 1
        end
      end
      puts "  resolved #{resolved}, no usable path in #{skipped}"
    end

    puts "done: #{resolved} listed, #{skipped} left without a category"
  end


  desc "Re-type imported catalogues that were created as classified (marketplace) stores. Dry run; APPLY=1 writes."
  task fix_imported_store_types: :environment do
    apply = ENV["APPLY"] == "1"

    # Imported rows are the ones carrying provenance. A store a person created
    # has no source_platform, so a genuine classified store is never touched.
    imported_storefronts = CommerceStorefront.where.not(source_platform: nil)
    storefront_scope = imported_storefronts.where(store_type: "marketplace")
    product_scope = CommerceProduct
      .where(store_type: "marketplace")
      .where(commerce_storefront_id: imported_storefronts.select(:id))

    # Counted before the update: the scopes are predicates on store_type, so
    # after a write they match nothing and a re-count would report zero rows
    # changed on a run that changed thousands.
    storefront_count = storefront_scope.count
    product_count = product_scope.count

    puts "imported storefronts       : #{imported_storefronts.count}"
    puts "storefronts to re-type      : #{storefront_count}"
    puts "products to re-type         : #{product_count}"

    if apply
      CommerceStorefront.transaction do
        storefront_scope.update_all(store_type: "ecommerce", updated_at: Time.current)
        product_scope.update_all(store_type: "ecommerce", updated_at: Time.current)
      end
      puts "applied: #{storefront_count} storefronts, #{product_count} products now ecommerce"
    else
      puts "dry run — re-run with APPLY=1 to write"
    end
  end


  desc "Re-file imported listings sitting on a marketplace catch-all store onto their real seller/brand store. Dry run; APPLY=1 writes."
  task attribute_imported_listings: :environment do
    apply = ENV["APPLY"] == "1"
    summary = Commerce::ListingAttribution.call(dry_run: !apply)

    puts summary
    puts(apply ? "applied" : "dry run — re-run with APPLY=1 to write")
  end


  desc "Fill imported storefront branding (banner, about, location, accent) from the listings already stored. Dry run; APPLY=1 writes."
  task backfill_storefront_branding: :environment do
    apply = ENV["APPLY"] == "1"
    summary = Commerce::StorefrontBrandingBackfill.call(dry_run: !apply)

    puts summary
    puts(apply ? "applied" : "dry run — re-run with APPLY=1 to write")
  end
end
