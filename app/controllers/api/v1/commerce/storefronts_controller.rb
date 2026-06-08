# frozen_string_literal: true

class Api::V1::Commerce::StorefrontsController < Api::V1::Commerce::BaseController
  def index
    require_scope("commerce:read")

    # Merchants viewing their own storefronts should see all statuses;
    # public discovery only shows published.
    if params[:merchant_id].present?
      storefronts = ::CommerceStorefront.includes(:commerce_merchant).order(created_at: :desc)
      storefronts = storefronts.joins(:commerce_merchant).where(commerce_merchants: { merchant_id: params[:merchant_id] })
    else
      storefronts = ::CommerceStorefront.published.includes(:commerce_merchant).order(created_at: :desc)
    end
    storefronts = storefronts.where(featured: true) if params[:featured] == "true"

    if params[:search].present?
      query = "%#{params[:search].downcase}%"
      storefronts = storefronts.where("LOWER(display_name) LIKE ? OR LOWER(description) LIKE ?", query, query)
    end

    storefronts = storefronts.limit(limit_param(default: 20, max: 100))

    render json: {
      storefronts: storefronts.map { |s| storefront_json(s, detail: :public) },
      meta: { total: storefronts.count }
    }
  end

  def create
    require_scope("commerce:merchant")

    merchant = find_merchant
    return if ensure_merchant_owner(merchant)

    storefront = merchant.commerce_storefronts.new(storefront_params)
    storefront.status = "published" if storefront.status.blank?

    if storefront.save
      render json: { storefront: storefront_json(storefront, detail: :full) }, status: :created
    else
      render_errors(storefront)
    end
  end

  def show
    require_scope("commerce:read")

    storefront = find_storefront
    storefront.increment!(:view_count)

    render json: {
      storefront: storefront_json(storefront, detail: :full),
      products: storefront.commerce_products.active.limit(20).map { |p| product_json(p, detail: :public) }
    }
  end

  def by_slug
    require_scope("commerce:read")

    storefront = ::CommerceStorefront.find_by!(store_url_slug: params[:slug])
    storefront.increment!(:view_count)

    render json: {
      storefront: storefront_json(storefront, detail: :full),
      products: storefront.commerce_products.active.limit(20).map { |p| product_json(p, detail: :public) }
    }
  end

  def update
    require_scope("commerce:merchant")

    storefront = find_storefront
    return if ensure_merchant_owner(storefront.commerce_merchant)

    if storefront.update(storefront_params)
      render json: { storefront: storefront_json(storefront, detail: :full) }
    else
      render_errors(storefront)
    end
  end

  def destroy
    require_scope("commerce:merchant")

    storefront = find_storefront
    return if ensure_merchant_owner(storefront.commerce_merchant)

    storefront.update!(status: "closed")
    render json: { storefront: storefront_json(storefront, detail: :public) }
  end

  def stats
    require_scope("commerce:merchant")

    storefront = find_storefront
    return if ensure_merchant_owner(storefront.commerce_merchant)

    orders = storefront.commerce_merchant.commerce_orders.where.not(status: %w[pending_payment cancelled])

    render json: {
      stats: {
        total_revenue_cents: orders.sum(:total_cents),
        total_orders: orders.count,
        total_products: storefront.commerce_products.count,
        total_views: storefront.view_count,
        rating_average: storefront.rating_average,
        rating_count: storefront.rating_count
      }
    }
  end

  private

  def find_storefront
    ::CommerceStorefront.find_by!(storefront_id: params[:id])
  end

  def storefront_params
    params.require(:storefront).permit(
      :display_name, :slug, :description, :status, :logo_url, :banner_url,
      :accent_color, :about, :featured, :social_share_enabled,
      :seo_title, :seo_description, policies: {}
    )
  end

  def limit_param(default:, max:)
    [ (params[:limit] || default).to_i, max ].min
  end
end
