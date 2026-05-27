# frozen_string_literal: true

class Api::V1::Commerce::CheckoutsController < Api::V1::Commerce::BaseController
  def create
    require_scope("commerce:checkout")

    cart = find_cart
    return if ensure_cart_owner(cart)
    if idempotency_key.present?
      existing_checkout = ::CommerceCheckout.find_by(buyer_user_id: @current_user.matrix_user_id, idempotency_key: idempotency_key)
      return render_existing_checkout(existing_checkout) if existing_checkout
    end

    checkout = nil
    order = nil
    ::CommerceCheckout.transaction do
      cart.recalculate!
      reserve_inventory!(cart)
      payment_data = create_payment_request(cart)
      checkout = ::CommerceCheckout.create!(
        commerce_cart: cart,
        commerce_merchant: cart.commerce_merchant,
        buyer_user_id: @current_user.matrix_user_id,
        status: "payment_pending",
        payment_id: payment_data.fetch(:payment_id),
        idempotency_key: idempotency_key,
        metadata: checkout_metadata.merge("payment" => payment_data, "inventory_reserved" => true)
      )
      order = create_order_from_checkout(checkout, cart)
      checkout.update!(order_id: order.order_id)
      cart.update!(status: "checked_out")
    end

    render json: { checkout: checkout_json(checkout.reload), order: order_json(order), cart: cart_json(cart.reload) }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render_errors(e.record)
  end

  def show
    require_scope("commerce:checkout")

    checkout = find_checkout
    return if ensure_cart_owner(checkout.commerce_cart)

    render json: { checkout: checkout_json(checkout) }
  end

  def authorize
    require_scope("commerce:checkout")

    checkout = find_checkout
    return if ensure_cart_owner(checkout.commerce_cart)

    result = WalletService.authorize_payment(checkout.payment_id, authorization_params.to_h, @tep_token)
    order = ::CommerceOrder.find_by!(order_id: checkout.order_id)
    checkout.update!(status: "completed", metadata: checkout.metadata.merge("authorization" => result))
    order.update!(status: "paid", metadata: order.metadata.merge("authorization" => result))
    emit_order_created(order)
    emit_checkout_created(checkout)

    render json: { checkout: checkout_json(checkout), order: order_json(order) }
  rescue WalletService::WalletError => e
    checkout&.update!(status: "failed", metadata: checkout.metadata.merge("payment_error" => e.message))
    render json: { error: "payment_failed", message: e.message }, status: :payment_required
  end

  def cancel
    require_scope("commerce:checkout")

    checkout = find_checkout
    return if ensure_cart_owner(checkout.commerce_cart)

    order = ::CommerceOrder.find_by(order_id: checkout.order_id)
    checkout.update!(status: "cancelled")
    restore_inventory!(order) if order
    order&.update!(status: "cancelled", metadata: order.metadata.merge("inventory_restored" => true))

    render json: { checkout: checkout_json(checkout), order: order ? order_json(order) : nil }
  end

  private

  def checkout_metadata
    return {} if params[:checkout].blank?

    params.require(:checkout).permit(shipping_address: {}, billing_address: {}, metadata: {}).to_h
  end

  def create_order_from_checkout(checkout, cart)
    ::CommerceOrder.create!(
      commerce_merchant: cart.commerce_merchant,
      buyer_user_id: cart.buyer_user_id,
      payment_id: checkout.payment_id,
      status: "pending_payment",
      subtotal_cents: cart.subtotal_cents,
      tax_cents: cart.tax_cents,
      shipping_cents: cart.shipping_cents,
      discount_cents: cart.discount_cents,
      total_cents: cart.total_cents,
      currency: cart.currency,
      metadata: { checkout_id: checkout.checkout_id }
    ).tap do |order|
      cart.commerce_cart_items.includes(commerce_sku: :commerce_product).find_each do |cart_item|
        sku = cart_item.commerce_sku
        order.commerce_order_items.create!(
          sku_id: sku.sku_id,
          product_id: sku.commerce_product.product_id,
          title: sku.title,
          quantity: cart_item.quantity,
          unit_price_cents: cart_item.unit_price_cents,
          line_total_cents: cart_item.line_total_cents,
          currency: cart_item.currency
        )
      end
    end
  end

  def reserve_inventory!(cart)
    cart.commerce_cart_items.includes(:commerce_sku).each do |item|
      sku = item.commerce_sku
      next if sku.quantity_available.nil?
      raise ActiveRecord::RecordInvalid, item unless sku.available?(item.quantity)

      sku.update!(quantity_available: sku.quantity_available - item.quantity)
    end
  end

  def restore_inventory!(order)
    return if order.metadata["inventory_restored"]

    order.commerce_order_items.each do |item|
      sku = ::CommerceSku.find_by(sku_id: item.sku_id)
      next unless sku&.quantity_available

      sku.update!(quantity_available: sku.quantity_available + item.quantity)
    end
  end

  def create_payment_request(cart)
    amount = cart.total_cents.to_d / 100
    WalletService.create_payment_request(
      amount,
      cart.currency,
      "Commerce checkout #{cart.cart_id}",
      @tep_token,
      merchant_order_id: cart.cart_id.upcase.gsub(/[^A-Z0-9\-_]/, "_"),
      callback_url: "https://tmcp.local/api/v1/commerce/checkouts/callback",
      items: cart.commerce_cart_items.includes(:commerce_sku).map { |item| payment_item(item) },
      idempotency_key: idempotency_key || cart.cart_id
    ).with_indifferent_access
  rescue WalletService::WalletError => e
    {
      payment_id: "pay_#{SecureRandom.urlsafe_base64(18)}",
      status: "wallet_unavailable",
      error: e.message
    }.with_indifferent_access
  end

  def payment_item(item)
    {
      item_id: item.commerce_sku.sku_id,
      name: item.commerce_sku.title,
      quantity: item.quantity,
      unit_price: item.unit_price_cents.to_d / 100
    }
  end

  def authorization_params
    return ActionController::Parameters.new.permit! if params[:authorization].blank?

    params.require(:authorization).permit(:signature, :device_id, :timestamp, :mfa_token, metadata: {})
  end

  def idempotency_key
    @idempotency_key ||= request.headers["Idempotency-Key"].presence || params[:idempotency_key].presence
  end

  def render_existing_checkout(checkout)
    order = ::CommerceOrder.find_by(order_id: checkout.order_id)
    render json: {
      checkout: checkout_json(checkout),
      order: order ? order_json(order) : nil,
      cart: cart_json(checkout.commerce_cart),
      idempotent_replay: true
    }
  end

  def emit_order_created(order)
    MatrixEventService.publish_order_created(
      order_id: order.order_id,
      payment_id: order.payment_id,
      merchant_id: order.commerce_merchant.merchant_id,
      buyer_user_id: order.buyer_user_id,
      status: order.status,
      total: { amount: order.total_cents.to_s, currency: order.currency }
    )
  end

  def emit_checkout_created(checkout)
    MatrixEventService.publish_checkout_created(
      checkout_id: checkout.checkout_id,
      cart_id: checkout.commerce_cart.cart_id,
      merchant_id: checkout.commerce_merchant.merchant_id,
      buyer_user_id: checkout.buyer_user_id,
      expires_at: checkout.expires_at.iso8601
    )
  end
end
