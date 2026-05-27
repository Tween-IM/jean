class Api::V1::Commerce::CheckoutsController < Api::V1::Commerce::BaseController
  def create
    require_scope("commerce:checkout")

    cart = find_cart
    return if ensure_cart_owner(cart)

    cart.recalculate!
    checkout = ::CommerceCheckout.create!(
      commerce_cart: cart,
      commerce_merchant: cart.commerce_merchant,
      buyer_user_id: @current_user.matrix_user_id,
      status: "payment_pending",
      payment_id: "pay_#{SecureRandom.urlsafe_base64(18)}",
      metadata: checkout_metadata
    )
    order = create_order_from_checkout(checkout, cart)
    checkout.update!(order_id: order.order_id)
    cart.update!(status: "checked_out")

    render json: { checkout: checkout_json(checkout.reload), order: order_json(order), cart: cart_json(cart.reload) }, status: :created
  end

  def show
    require_scope("commerce:checkout")

    checkout = find_checkout
    return if ensure_cart_owner(checkout.commerce_cart)

    render json: { checkout: checkout_json(checkout) }
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
end
