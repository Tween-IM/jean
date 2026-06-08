# frozen_string_literal: true

class Api::V1::Commerce::ProductsController < Api::V1::Commerce::BaseController
  def index
    require_scope("commerce:read")

    products = ::CommerceProduct.active.includes(:commerce_merchant, :commerce_skus, :commerce_category).order(created_at: :desc)
    products = products.joins(:commerce_merchant).where(commerce_merchants: { merchant_id: params[:merchant_id] }) if params[:merchant_id].present?
    products = products.where(commerce_storefront_id: ::CommerceStorefront.where(storefront_id: params[:storefront_id]).select(:id)) if params[:storefront_id].present?
    products = products.where(category_id: ::CommerceCategory.where(category_id: params[:category_id]).select(:id)) if params[:category_id].present?

    if params[:min_price].present?
      min_price = params[:min_price].to_i
      products = products.joins(:commerce_skus).where("commerce_skus.price_cents >= ?", min_price)
    end

    if params[:max_price].present?
      max_price = params[:max_price].to_i
      products = products.joins(:commerce_skus).where("commerce_skus.price_cents <= ?", max_price)
    end

    if params[:search].present?
      query = "%#{params[:search].downcase}%"
      products = products.where("LOWER(title) LIKE ? OR LOWER(description) LIKE ? OR ? = ANY(tags)", query, query, params[:search].downcase)
    end

    # Sorting
    products = case params[:sort]
               when "price_asc" then products.joins(:commerce_skus).order("commerce_skus.price_cents ASC")
               when "price_desc" then products.joins(:commerce_skus).order("commerce_skus.price_cents DESC")
               when "popular" then products.order(sales_count: :desc, view_count: :desc)
               when "rating" then products.order(rating_average: :desc)
               else products.order(created_at: :desc)
               end

    products = products.distinct.limit(limit_param(default: 20, max: 100))

    render json: {
      products: products.map { |p| product_json(p, detail: :public) },
      meta: { total: products.count }
    }
  end

  def featured
    require_scope("commerce:read")

    products = ::CommerceProduct.active.where(featured: true).includes(:commerce_merchant).order(created_at: :desc).limit(20)
    render json: { products: products.map { |p| product_json(p, detail: :public) } }
  end

  def trending
    require_scope("commerce:read")

    products = ::CommerceProduct.active.order(sales_count: :desc, view_count: :desc).includes(:commerce_merchant).limit(20)
    render json: { products: products.map { |p| product_json(p, detail: :public) } }
  end

  def search
    require_scope("commerce:read")

    query = params[:q].to_s.strip
    category_id = params[:category_id]
    sort = params[:sort]

    if query.length < 2 && category_id.blank?
      render json: { products: [], meta: { total: 0 } }
      return
    end

    scope = ::CommerceProduct.active.includes(:commerce_merchant, :commerce_skus)

    if query.length >= 2
      search_query = "%#{query.downcase}%"
      scope = scope.where(
        "LOWER(title) LIKE ? OR LOWER(description) LIKE ? OR ? = ANY(tags)",
        search_query, search_query, query.downcase
      )
    end

    if category_id.present?
      scope = scope.where(
        category_id: ::CommerceCategory.where(category_id: category_id).select(:id)
      )
    end

    scope = case sort
            when "price_asc" then scope.joins(:commerce_skus).order("commerce_skus.price_cents ASC")
            when "price_desc" then scope.joins(:commerce_skus).order("commerce_skus.price_cents DESC")
            when "newest" then scope.order(created_at: :desc)
            when "popular" then scope.order(sales_count: :desc)
            when "rating" then scope.order(rating_average: :desc)
            else scope.order(created_at: :desc)
            end

    products = scope.limit(limit_param(default: 20, max: 50))

    render json: {
      products: products.map { |p| product_json(p, detail: :public) },
      meta: { total: products.count, query: query }
    }
  end

  def show
    require_scope("commerce:read")

    product = find_product
    product.increment!(:view_count)

    related = ::CommerceProduct.active
      .where.not(product_id: product.product_id)
      .where(category_id: product.category_id)
      .limit(4)

    render json: {
      product: product_json(product, detail: :full),
      reviews: product.commerce_reviews.approved.limit(10).map { |r| review_json(r) },
      related_products: related.map { |p| product_json(p, detail: :public) }
    }
  end

  def create
    require_scope("commerce:merchant")

    merchant = find_merchant
    return if ensure_merchant_owner(merchant)

    permitted = product_params
    permitted[:title] = permitted.delete(:name) if permitted[:name].present?

    product = merchant.commerce_products.new(permitted)
    assign_storefront(product)
    assign_category(product)

    if product.save
      begin
        ActiveRecord::Base.transaction do
          create_skus(product)
          link_shipping_profiles(product)
        end
        product.commerce_storefront&.recache_stats!
        render json: { product: product_json(product.reload, detail: :full) }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        product.destroy
        render json: { error: "validation_failed", message: e.message }, status: :unprocessable_entity
      end
    else
      render_errors(product)
    end
  end

  def update
    require_scope("commerce:merchant")

    product = find_product
    return if ensure_merchant_owner(product.commerce_merchant)

    assign_storefront(product)
    assign_category(product)

    permitted = product_params
    permitted[:title] = permitted.delete(:name) if permitted[:name].present?

    if product.update(permitted)
      update_skus(product) if params[:skus].present?
      link_shipping_profiles(product) if params[:shipping_profile_ids].present?
      product.commerce_storefront&.recache_stats!
      render json: { product: product_json(product.reload, detail: :full) }
    else
      render_errors(product)
    end
  end

  def destroy
    require_scope("commerce:merchant")

    product = find_product
    return if ensure_merchant_owner(product.commerce_merchant)

    product.update!(status: "archived")
    product.commerce_storefront&.recache_stats!
    render json: { product: product_json(product, detail: :public) }
  end

  private

  def product_params
    params.require(:product).permit(
      :title, :name, :description, :status, :condition, :featured,
      :weight_grams, :seo_title, :seo_description,
      media_urls: [], tags: [], dimensions: {}
    )
  end

  def assign_storefront(product)
    if params[:storefront_id].present?
      product.commerce_storefront = product.commerce_merchant.commerce_storefronts.find_by!(storefront_id: params[:storefront_id])
    else
      # Products require a storefront. Auto-create a default one if the merchant
      # doesn't have any yet (e.g. individual sellers who skipped storefront setup).
      product.commerce_storefront = product.commerce_merchant.commerce_storefronts.first_or_create! do |sf|
        sf.display_name = product.commerce_merchant.display_name
        sf.status = "published"
      end
    end
  end

  def assign_category(product)
    return if params[:category_id].blank?

    product.commerce_category = ::CommerceCategory.find_by!(category_id: params[:category_id])
  end

  def create_skus(product)
    Array(params[:skus]).each do |sku_params|
      sku_hash = sku_params.respond_to?(:to_unsafe_h) ? sku_params.to_unsafe_h : sku_params
      permitted_sku = ActionController::Parameters.new(sku_hash).permit(
        :title, :price_cents, :currency, :inventory_status, :quantity_available, properties: {}
      )
      permitted_sku[:currency] ||= 'NGN'
      product.commerce_skus.create!(permitted_sku)
    end
  end

  def update_skus(product)
    Array(params[:skus]).each do |sku_params|
      sku_hash = sku_params.respond_to?(:to_unsafe_h) ? sku_params.to_unsafe_h : sku_params
      if sku_hash["sku_id"].present?
        permitted = ActionController::Parameters.new(sku_hash.except("sku_id")).permit(:title, :price_cents, :currency, :inventory_status, :quantity_available, properties: {})
        permitted[:currency] ||= 'NGN'
        sku = product.commerce_skus.find_by(sku_id: sku_hash["sku_id"])
        sku&.update!(permitted)
      else
        permitted_sku = ActionController::Parameters.new(sku_hash).permit(
          :title, :price_cents, :currency, :inventory_status, :quantity_available, properties: {}
        )
        permitted_sku[:currency] ||= 'NGN'
        product.commerce_skus.create!(permitted_sku)
      end
    end
  end

  def link_shipping_profiles(product)
    product.commerce_product_shipping.destroy_all
    Array(params[:shipping_profile_ids]).each do |profile_id|
      profile = product.commerce_merchant.commerce_shipping_profiles.find_by(shipping_profile_id: profile_id)
      product.commerce_product_shipping.create!(commerce_shipping_profile: profile) if profile
    end
  end

  def limit_param(default:, max:)
    [ (params[:limit] || default).to_i, max ].min
  end
end
