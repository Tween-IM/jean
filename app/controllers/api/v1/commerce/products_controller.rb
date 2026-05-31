# frozen_string_literal: true

class Api::V1::Commerce::ProductsController < Api::V1::Commerce::BaseController
  def index
    require_scope("commerce:read")

    products = ::CommerceProduct.active.includes(:commerce_merchant, :commerce_skus).order(created_at: :desc).limit(50)
    products = products.joins(:commerce_merchant).where(commerce_merchants: { merchant_id: params[:merchant_id] }) if params[:merchant_id].present?

    render json: { products: products.map { |product| product_json(product) } }
  end

  def show
    require_scope("commerce:read")

    render json: { product: product_json(find_product) }
  end

  def create
    require_scope("commerce:merchant")

    merchant = find_merchant
    return if ensure_merchant_owner(merchant)

    product = merchant.commerce_products.new(product_params)
    assign_storefront(product)

    if product.save
      create_skus(product)
      render json: { product: product_json(product.reload) }, status: :created
    else
      render_errors(product)
    end
  end

  private

  def product_params
    params.require(:product).permit(:title, :description, :status, media_urls: [])
  end

  def assign_storefront(product)
    return if params[:storefront_id].blank?

    product.commerce_storefront = product.commerce_merchant.commerce_storefronts.find_by!(storefront_id: params[:storefront_id])
  end

  def create_skus(product)
    Array(params[:skus]).each do |sku_params|
      sku_hash = sku_params.respond_to?(:to_unsafe_h) ? sku_params.to_unsafe_h : sku_params
      permitted_sku = ActionController::Parameters.new(sku_hash).permit(:title, :price_cents, :currency, :inventory_status, :quantity_available, properties: {})
      product.commerce_skus.create!(permitted_sku)
    end
  end
end
