# frozen_string_literal: true

class Api::V1::Commerce::DiscoverController < Api::V1::Commerce::BaseController
  def home
    require_scope("commerce:read")

    featured_stores = ::CommerceStorefront.published.where(featured: true).includes(:commerce_merchant).limit(10)
    trending_products = ::CommerceProduct.active.with_available_stock.order(sales_count: :desc, view_count: :desc).includes(:commerce_merchant).limit(10)
    featured_products = ::CommerceProduct.active.with_available_stock.where(featured: true).includes(:commerce_merchant).limit(10)
    categories = ::CommerceCategory.active.top_level.includes(:subcategories).order(:sort_order).limit(12)

    render json: {
      featured_stores: featured_stores.map { |s| storefront_json(s, detail: :public) },
      trending_products: trending_products.map { |p| product_json(p, detail: :public) },
      featured_products: featured_products.map { |p| product_json(p, detail: :public) },
      categories: categories.map { |c| category_json(c).merge(subcategories: c.subcategories.active.map { |sc| category_json(sc) }) }
    }
  end
end
