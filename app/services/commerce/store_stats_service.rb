# frozen_string_literal: true

module Commerce
  class StoreStatsService
    def self.update_storefront_stats(storefront)
      storefront.update!(
        product_count: storefront.commerce_products.where(status: "active").count,
        order_count: storefront.commerce_merchant.commerce_orders.where.not(status: %w[pending_payment cancelled]).count
      )
    end

    def self.update_product_stats(product)
      reviews = product.commerce_reviews.where(status: "approved")
      product.update!(
        rating_average: reviews.any? ? (reviews.sum(:rating).to_f / reviews.count).round(2) : nil,
        rating_count: reviews.count
      )
    end

    def self.update_merchant_stats(merchant)
      merchant.commerce_storefronts.each do |storefront|
        update_storefront_stats(storefront)
      end

      merchant.commerce_products.each do |product|
        update_product_stats(product)
      end
    end
  end
end
