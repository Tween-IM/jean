# frozen_string_literal: true

class Api::V1::Commerce::CheckoutsController < Api::V1::Commerce::BaseController
  skip_before_action :authenticate_tep_token, only: [:callback]

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
      apply_shipping!(cart)
      cart.recalculate!
      ::Commerce::InventoryService.reserve!(cart)
      payment_data = create_payment_request(cart)
      checkout = ::CommerceCheckout.create!(
        commerce_cart: cart,
        commerce_merchant: cart.commerce_merchant,
        buyer_user_id: @current_user.matrix_user_id,
        status: "payment_pending",
        payment_id: payment_data.fetch(:payment_id),
        idempotency_key: idempotency_key,
        metadata: checkout_metadata.merge("payment" => payment_data, "inventory_reserved" => true),
        shipping_address_line1: shipping_address["address_line1"],
        shipping_address_line2: shipping_address["address_line2"],
        shipping_city: shipping_address["city"],
        shipping_state: shipping_address["state"],
        shipping_postal_code: shipping_address["postal_code"],
        shipping_country: shipping_address["country"] || "NG",
        shipping_phone: shipping_address["phone"]
      )
      order = create_order_from_checkout(checkout, cart)
      checkout.update!(order_id: order.order_id)
      cart.update!(status: "checked_out")
    end

    render json: { checkout: checkout_json(checkout.reload), order: order_json(order), cart: cart_json(cart.reload) }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render_errors(e.record)
  rescue WalletService::WalletError => e
    render json: { error: "payment_failed", message: e.message }, status: :service_unavailable
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

    # Build auth_proof from authorization params + payment_method fallback
    auth_proof = authorization_params.to_h
    auth_proof[:payment_method] = params[:payment_method] if params[:payment_method].present?

    result = WalletService.authorize_payment(checkout.payment_id, auth_proof, @tep_token)
    order = ::CommerceOrder.find_by!(order_id: checkout.order_id)
    checkout.update!(status: "completed", metadata: checkout.metadata.merge("authorization" => result))
    order.update!(status: "paid", metadata: order.metadata.merge("authorization" => result))
    increment_sales_count!(order)
    emit_order_created(order)
    emit_checkout_created(checkout)

    render json: { checkout: checkout_json(checkout), order: order_json(order) }
  rescue WalletService::WalletError => e
    order = ::CommerceOrder.find_by(order_id: checkout.order_id)
    ::Commerce::InventoryService.restore!(order) if order
    checkout&.update!(status: "failed", metadata: checkout.metadata.merge("payment_error" => e.message, "inventory_restored" => true))
    order&.update!(status: "cancelled", metadata: order.metadata.merge("inventory_restored" => true, "cancelled_reason" => "payment_failed"))
    # Surface wallet-specific error codes so the frontend can show actionable messages
    error_code = e.code&.to_s&.downcase || "payment_failed"
    user_message = case error_code
    when "payment_access_denied"
      "Payment access denied. Please complete wallet verification in TweenPay."
    when "insufficient_funds"
      "Insufficient funds. Please top up your wallet."
    when "insufficient_scope"
      "Payment authorization failed. Please sign out and back in."
    else
      e.message
    end
    render json: { error: error_code, message: user_message }, status: :payment_required
  end

  def cancel
    require_scope("commerce:checkout")

    checkout = find_checkout
    return if ensure_cart_owner(checkout.commerce_cart)

    order = ::CommerceOrder.find_by(order_id: checkout.order_id)
    checkout.update!(status: "cancelled")
    ::Commerce::InventoryService.restore!(order) if order
    order&.update!(status: "cancelled", metadata: order.metadata.merge("inventory_restored" => true))

    render json: { checkout: checkout_json(checkout), order: order ? order_json(order) : nil }
  end

  def callback
    # Validate webhook signature from wallet service
    unless valid_callback_signature?
      return render json: { error: "unauthorized", message: "Invalid signature" }, status: :unauthorized
    end

    payment_id = params[:payment_id]
    checkout = ::CommerceCheckout.find_by(payment_id: payment_id)

    unless checkout
      return render json: { error: "not_found", message: "Checkout not found" }, status: :not_found
    end

    # Idempotent: ignore if already processed
    if checkout.status.in?(%w[completed failed cancelled expired])
      return head :ok
    end

    order = ::CommerceOrder.find_by(order_id: checkout.order_id)
    payment_status = params[:status]

    if payment_status == "completed"
      checkout.update!(status: "completed", metadata: checkout.metadata.merge("callback_processed_at" => Time.current.iso8601))
      order&.update!(status: "paid", metadata: order.metadata.merge("callback_processed_at" => Time.current.iso8601))
      increment_sales_count!(order) if order
      emit_order_created(order) if order
      emit_checkout_created(checkout)
    else
      ::Commerce::InventoryService.restore!(order) if order
      checkout.update!(status: "failed", metadata: checkout.metadata.merge("payment_error" => params[:error] || "callback_failed", "inventory_restored" => true, "callback_processed_at" => Time.current.iso8601))
      order&.update!(status: "cancelled", metadata: order.metadata.merge("inventory_restored" => true, "cancelled_reason" => "payment_failed", "callback_processed_at" => Time.current.iso8601))
    end

    head :ok
  end

  private

  def checkout_metadata
    return {} if params[:checkout].blank?

    params.require(:checkout).permit(
      :shipping_address_line1,
      :shipping_address_line2,
      :shipping_city,
      :shipping_state,
      :shipping_postal_code,
      :shipping_country,
      :shipping_phone,
      :billing_address_line1,
      :billing_address_line2,
      :billing_city,
      :billing_state,
      :billing_postal_code,
      :billing_country,
      metadata: {}
    ).to_h
  end

  def shipping_address
    @shipping_address ||= begin
      address = params[:shipping_address] || ActionController::Parameters.new
      address = ActionController::Parameters.new(address) unless address.respond_to?(:permit)
      address.permit(
        :full_name, :phone, :address_line1, :address_line2, :city, :state,
        :postal_code, :country
      ).to_h
    end
  end

  def apply_shipping!(cart)
    profile_id = params[:shipping_profile_id].presence
    return if profile_id.blank?

    profile = cart.commerce_merchant.commerce_shipping_profiles.active.find_by!(
      shipping_profile_id: profile_id
    )
    quote = profile.calculate_shipping(
      destination_country: shipping_address["country"].presence || "NG",
      destination_state: shipping_address["state"].presence,
      weight_grams: cart.commerce_cart_items
        .joins(commerce_sku: :commerce_product)
        .sum("COALESCE(commerce_products.weight_grams, 0)"),
      subtotal_cents: cart.subtotal_cents
    )
    raise ActiveRecord::RecordInvalid, cart if quote[:rate_cents].nil?

    cart.update!(shipping_cents: quote[:rate_cents])
  end

  def create_order_from_checkout(checkout, cart)
    ::CommerceOrder.create!(
      commerce_merchant: cart.commerce_merchant,
      buyer_user_id: cart.buyer_user_id,
      payment_id: checkout.payment_id,
      status: "pending_payment",
      shipping_address_line1: checkout.shipping_address_line1,
      shipping_address_line2: checkout.shipping_address_line2,
      shipping_city: checkout.shipping_city,
      shipping_state: checkout.shipping_state,
      shipping_postal_code: checkout.shipping_postal_code,
      shipping_country: checkout.shipping_country,
      shipping_phone: checkout.shipping_phone,
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
        product = sku.commerce_product
        order.commerce_order_items.create!(
          sku_id: sku.sku_id,
          product_id: product.product_id,
          title: sku.title,
          product_name: product.title,
          product_media_url: product.media_urls.first,
          variant_attributes: cart_item.variant_attributes,
          quantity: cart_item.quantity,
          unit_price_cents: cart_item.unit_price_cents,
          line_total_cents: cart_item.line_total_cents,
          currency: cart_item.currency
        )
      end
    end
  end

  def create_payment_request(cart)
    amount = cart.total_cents.to_d / 100
    callback_url = ENV.fetch("COMMERCE_CHECKOUT_CALLBACK_URL", "#{ENV.fetch('TMCP_BASE_URL', 'https://tmcp.local')}/api/v1/commerce/checkouts/callback")
    merchant = cart.commerce_merchant

    WalletService.create_payment_request(
      amount,
      cart.currency,
      "Commerce checkout #{cart.cart_id}",
      @tep_token,
      merchant_order_id: cart.cart_id.upcase.gsub(/[^A-Z0-9\-_]/, "_"),
      callback_url: callback_url,
      items: cart.commerce_cart_items.includes(:commerce_sku).map { |item| payment_item(item) },
      idempotency_key: idempotency_key || cart.cart_id,
      metadata: {
        commission_rate: merchant.commission_rate,
        merchant_owner_matrix_id: merchant.owner_user_id,
        merchant_business_name: merchant.display_name
      }
    ).with_indifferent_access
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

  def increment_sales_count!(order)
    order.commerce_order_items.group_by(&:product_id).each do |product_id, items|
      product = ::CommerceProduct.find_by(product_id: product_id)
      next unless product

      product.increment!(:sales_count, items.sum(&:quantity))
    end
  end

  def valid_callback_signature?
    secret = ENV.fetch("WEBHOOK_SECRET", "")
    return true if secret.blank? # Allow in development if secret not set

    signature = request.headers["X-TMCP-Signature"]
    return false if signature.blank?

    payload = request.body.read
    request.body.rewind
    expected = OpenSSL::HMAC.hexdigest("SHA256", secret, payload)
    ActiveSupport::SecurityUtils.secure_compare(signature, expected)
  end
end
