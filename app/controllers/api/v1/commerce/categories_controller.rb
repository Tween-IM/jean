# frozen_string_literal: true

class Api::V1::Commerce::CategoriesController < Api::V1::Commerce::BaseController
  def index
    require_scope("commerce:read")

    categories = ::CommerceCategory.active.top_level.includes(:subcategories).order(:sort_order)
    render json: {
      categories: categories.map { |c| category_with_children_json(c) }
    }
  end

  def show
    require_scope("commerce:read")

    category = find_category
    products = category.commerce_products.active.includes(:commerce_merchant, :commerce_skus).order(created_at: :desc).limit(50)

    render json: {
      category: category_with_children_json(category),
      products: products.map { |p| product_json(p, detail: :public) }
    }
  end

  private

  def category_with_children_json(category)
    base = category_json(category)
    base[:subcategories] = category.subcategories.active.map { |sc| category_json(sc) }
    base
  end
end
