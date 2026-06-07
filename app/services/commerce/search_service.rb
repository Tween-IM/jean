# frozen_string_literal: true

module Commerce
  class SearchService
    def self.search_products(query:, filters: {})
      products = ::CommerceProduct.active.includes(:commerce_merchant, :commerce_skus, :commerce_category)

      if query.present? && query.length >= 2
        search_term = "%#{query.downcase}%"
        products = products.where(
          "LOWER(title) LIKE ? OR LOWER(description) LIKE ? OR ? = ANY(tags)",
          search_term, search_term, query.downcase
        )
      end

      products = apply_filters(products, filters)
      products = apply_sort(products, filters[:sort])

      products.distinct
    end

    def self.search_storefronts(query:)
      storefronts = ::CommerceStorefront.published.includes(:commerce_merchant)

      if query.present? && query.length >= 2
        search_term = "%#{query.downcase}%"
        storefronts = storefronts.where(
          "LOWER(display_name) LIKE ? OR LOWER(description) LIKE ?",
          search_term, search_term
        )
      end

      storefronts
    end

    private

    def self.apply_filters(products, filters)
      if filters[:merchant_id].present?
        products = products.joins(:commerce_merchant).where(commerce_merchants: { merchant_id: filters[:merchant_id] })
      end

      if filters[:storefront_id].present?
        storefront = ::CommerceStorefront.find_by(storefront_id: filters[:storefront_id])
        products = products.where(commerce_storefront_id: storefront.id) if storefront
      end

      if filters[:category_id].present?
        category = ::CommerceCategory.find_by(category_id: filters[:category_id])
        products = products.where(category_id: category.id) if category
      end

      if filters[:min_price].present?
        products = products.joins(:commerce_skus).where("commerce_skus.price_cents >= ?", filters[:min_price].to_i)
      end

      if filters[:max_price].present?
        products = products.joins(:commerce_skus).where("commerce_skus.price_cents <= ?", filters[:max_price].to_i)
      end

      if filters[:condition].present?
        products = products.where(condition: filters[:condition])
      end

      products
    end

    def self.apply_sort(products, sort)
      case sort
      when "price_asc"
        products.joins(:commerce_skus).order("commerce_skus.price_cents ASC")
      when "price_desc"
        products.joins(:commerce_skus).order("commerce_skus.price_cents DESC")
      when "popular"
        products.order(sales_count: :desc, view_count: :desc)
      when "rating"
        products.order(rating_average: :desc)
      when "newest"
        products.order(created_at: :desc)
      else
        products.order(created_at: :desc)
      end
    end
  end
end
