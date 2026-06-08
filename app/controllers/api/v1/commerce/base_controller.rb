# frozen_string_literal: true

class Api::V1::Commerce::BaseController < Api::BaseController
  include Api::TepAuthenticatable
  include Api::RateLimitable

  before_action :authenticate_tep_token

  rate_limit action: :create, limit: 10, window: 60, key: "commerce:write::user_id"
  rate_limit action: :checkout, limit: 5, window: 60, key: "commerce:checkout::user_id"
  rate_limit action: :authorize, limit: 5, window: 60, key: "commerce:pay::user_id"

  private

  def find_merchant
    ::CommerceMerchant.find_by!(merchant_id: params[:merchant_id] || params[:id])
  end

  def find_product
    ::CommerceProduct.find_by!(product_id: params[:product_id] || params[:id])
  end

  def find_cart
    ::CommerceCart.find_by!(cart_id: params[:cart_id] || params[:id])
  end

  def find_checkout
    ::CommerceCheckout.find_by!(checkout_id: params[:checkout_id] || params[:id])
  end

  def find_order
    ::CommerceOrder.find_by!(order_id: params[:order_id] || params[:id])
  end

  def find_storefront
    ::CommerceStorefront.find_by!(storefront_id: params[:storefront_id] || params[:id])
  end

  def find_category
    ::CommerceCategory.find_by!(category_id: params[:category_id] || params[:id])
  end

  def find_review
    ::CommerceReview.find_by!(review_id: params[:review_id] || params[:id])
  end

  def find_warehouse
    ::CommerceWarehouse.find_by!(warehouse_id: params[:warehouse_id] || params[:id])
  end

  def find_shipping_profile
    ::CommerceShippingProfile.find_by!(shipping_profile_id: params[:shipping_profile_id] || params[:id])
  end

  def ensure_cart_owner(cart)
    return false if cart.buyer_user_id == @current_user.matrix_user_id

    render json: { error: "forbidden", message: "Cart belongs to another buyer" }, status: :forbidden
    true
  end

  def ensure_merchant_owner(merchant)
    return false if merchant.owner_user_id == @current_user.matrix_user_id

    render json: { error: "forbidden", message: "Merchant belongs to another owner" }, status: :forbidden
    true
  end

  def render_errors(record)
    render json: { error: "validation_failed", messages: record.errors.full_messages }, status: :unprocessable_entity
  end

  # ============================================================================
  # MERCHANT
  # ============================================================================

  def merchant_json(merchant, detail: :public)
    base = {
      merchant_id: merchant.merchant_id,
      owner_user_id: merchant.owner_user_id,
      miniapp_id: merchant.miniapp_id,
      display_name: merchant.display_name,
      status: merchant.status,
      wallet_id: merchant.wallet_id,
      webhook_url: merchant.webhook_url,
      logo_url: merchant.logo_url,
      banner_url: merchant.banner_url,
      business_type: merchant.business_type,
      phone: merchant.phone,
      email: merchant.email,
      website: merchant.website,
      city: merchant.city,
      state: merchant.state,
      country: merchant.country,
      about: merchant.about,
      verified_at: merchant.verified_at,
      commission_rate: merchant.commission_rate,
      created_at: merchant.created_at
    }

    if detail == :full
      base.merge!(
        registration_number: merchant.registration_number,
        address_line1: merchant.address_line1,
        address_line2: merchant.address_line2,
        policies: merchant.policies,
        social_links: merchant.social_links,
        payout_settings: merchant.payout_settings
      )
    end

    base
  end

  # ============================================================================
  # STOREFRONT
  # ============================================================================

  def storefront_json(storefront, detail: :public)
    base = {
      storefront_id: storefront.storefront_id,
      merchant_id: storefront.commerce_merchant.merchant_id,
      slug: storefront.slug,
      store_url_slug: storefront.store_url_slug,
      display_name: storefront.display_name,
      description: storefront.description,
      status: storefront.status,
      logo_url: storefront.logo_url,
      banner_url: storefront.banner_url,
      accent_color: storefront.accent_color,
      featured: storefront.featured,
      is_default: storefront.is_default,
      rating_average: storefront.rating_average,
      rating_count: storefront.rating_count,
      product_count: storefront.product_count,
      order_count: storefront.order_count,
      view_count: storefront.view_count,
      created_at: storefront.created_at,
      updated_at: storefront.updated_at
    }

    if detail == :full
      base.merge!(
        about: storefront.about,
        policies: storefront.policies,
        social_share_enabled: storefront.social_share_enabled,
        seo_title: storefront.seo_title,
        seo_description: storefront.seo_description,
        merchant: merchant_json(storefront.commerce_merchant, detail: :public)
      )
    end

    base
  end

  # ============================================================================
  # PRODUCT
  # ============================================================================

  def product_json(product, detail: :public)
    base = {
      product_id: product.product_id,
      merchant_id: product.commerce_merchant.merchant_id,
      merchant: merchant_json(product.commerce_merchant, detail: :public),
      storefront_id: product.commerce_storefront&.storefront_id,
      title: product.title,
      description: product.description,
      status: product.status,
      media_urls: product.media_urls,
      condition: product.condition,
      featured: product.featured,
      rating_average: product.rating_average,
      rating_count: product.rating_count,
      sales_count: product.sales_count,
      view_count: product.view_count,
      tags: product.tags,
      price_range: product.price_range,
      category: product.commerce_category ? category_json(product.commerce_category) : nil,
      created_at: product.created_at
    }

    if detail == :full
      base.merge!(
        weight_grams: product.weight_grams,
        dimensions: product.dimensions,
        seo_title: product.seo_title,
        seo_description: product.seo_description,
        skus: product.commerce_skus.map { |sku| sku_json(sku) },
        shipping_profiles: product.commerce_shipping_profiles.map { |sp| shipping_profile_json(sp) }
      )
    end

    base
  end

  # ============================================================================
  # SKU
  # ============================================================================

  def sku_json(sku)
    {
      sku_id: sku.sku_id,
      title: sku.title,
      price_cents: sku.price_cents,
      currency: sku.currency,
      inventory_status: sku.inventory_status,
      quantity_available: sku.quantity_available,
      properties: sku.properties
    }
  end

  # ============================================================================
  # CART
  # ============================================================================

  def cart_json(cart)
    {
      cart_id: cart.cart_id,
      merchant_id: cart.commerce_merchant.merchant_id,
      merchant_name: cart.commerce_merchant.display_name,
      buyer_user_id: cart.buyer_user_id,
      status: cart.status,
      subtotal_cents: cart.subtotal_cents,
      tax_cents: cart.tax_cents,
      shipping_cents: cart.shipping_cents,
      discount_cents: cart.discount_cents,
      total_cents: cart.total_cents,
      currency: cart.currency,
      items: cart.commerce_cart_items.includes(commerce_sku: :commerce_product).map { |item| cart_item_json(item) },
      updated_at: cart.updated_at
    }
  end

  def cart_item_json(item)
    {
      sku_id: item.commerce_sku.sku_id,
      product_id: item.commerce_sku.commerce_product.product_id,
      title: item.commerce_sku.title,
      quantity: item.quantity,
      unit_price_cents: item.unit_price_cents,
      line_total_cents: item.line_total_cents,
      currency: item.currency
    }
  end

  # ============================================================================
  # CHECKOUT
  # ============================================================================

  def checkout_json(checkout)
    {
      checkout_id: checkout.checkout_id,
      cart_id: checkout.commerce_cart.cart_id,
      status: checkout.status,
      payment_id: checkout.payment_id,
      order_id: checkout.order_id,
      total_cents: checkout.commerce_cart.total_cents,
      expires_at: checkout.expires_at,
      metadata: checkout.metadata,
      shipping_address: checkout.shipping_address,
      created_at: checkout.created_at
    }
  end

  # ============================================================================
  # ORDER
  # ============================================================================

  def order_json(order, detail: :public)
    base = {
      order_id: order.order_id,
      merchant_id: order.commerce_merchant.merchant_id,
      buyer_user_id: order.buyer_user_id,
      status: order.status,
      payment_id: order.payment_id,
      subtotal_cents: order.subtotal_cents,
      tax_cents: order.tax_cents,
      shipping_cents: order.shipping_cents,
      discount_cents: order.discount_cents,
      total_cents: order.total_cents,
      currency: order.currency,
      fulfillment_status: order.fulfillment_status,
      metadata: order.metadata,
      items: order.commerce_order_items.map { |item| order_item_json(item) },
      shipping_address: order.shipping_address,
      created_at: order.created_at
    }

    if detail == :full
      base[:merchant] = merchant_json(order.commerce_merchant, detail: :public)
    end

    base
  end

  def order_item_json(item)
    {
      sku_id: item.sku_id,
      product_id: item.product_id,
      title: item.title,
      product_name: item.product_name,
      product_media_url: item.product_media_url,
      variant_attributes: item.variant_attributes,
      quantity: item.quantity,
      unit_price_cents: item.unit_price_cents,
      line_total_cents: item.line_total_cents,
      currency: item.currency
    }
  end

  # ============================================================================
  # CATEGORY
  # ============================================================================

  def category_json(category)
    {
      category_id: category.category_id,
      name: category.name,
      slug: category.slug,
      description: category.description,
      icon: category.icon,
      parent_id: category.parent_id,
      product_count: category.product_count,
      status: category.status
    }
  end

  # ============================================================================
  # REVIEW
  # ============================================================================

  def review_json(review)
    {
      review_id: review.review_id,
      buyer_user_id: review.buyer_user_id,
      rating: review.rating,
      title: review.title,
      body: review.body,
      helpful_count: review.helpful_count,
      status: review.status,
      created_at: review.created_at
    }
  end

  # ============================================================================
  # WAREHOUSE
  # ============================================================================

  def warehouse_json(warehouse)
    {
      warehouse_id: warehouse.warehouse_id,
      name: warehouse.name,
      address_line1: warehouse.address_line1,
      address_line2: warehouse.address_line2,
      city: warehouse.city,
      state: warehouse.state,
      postal_code: warehouse.postal_code,
      country: warehouse.country,
      phone: warehouse.phone,
      is_default: warehouse.is_default,
      status: warehouse.status,
      created_at: warehouse.created_at
    }
  end

  # ============================================================================
  # SHIPPING PROFILE
  # ============================================================================

  def shipping_profile_json(profile)
    {
      shipping_profile_id: profile.shipping_profile_id,
      name: profile.name,
      processing_time_days: profile.processing_time_days,
      origin_warehouse_id: profile.origin_warehouse_id,
      zones: profile.zones,
      free_shipping_threshold_cents: profile.free_shipping_threshold_cents,
      status: profile.status,
      created_at: profile.created_at
    }
  end
end
