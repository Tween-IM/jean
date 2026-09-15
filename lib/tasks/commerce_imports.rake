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
end
