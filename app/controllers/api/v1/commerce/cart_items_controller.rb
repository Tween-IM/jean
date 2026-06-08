# frozen_string_literal: true

class Api::V1::Commerce::CartItemsController < Api::V1::Commerce::BaseController
  def update
    require_scope("commerce:cart")

    cart = find_cart
    return if ensure_cart_owner(cart)

    sku = ::CommerceSku.find_by!(sku_id: params[:sku_id])
    item = cart.commerce_cart_items.find_or_initialize_by(commerce_sku: sku)
    item.quantity = params.require(:quantity)
    item.currency = sku.currency
    item.unit_price_cents = sku.price_cents
    item.line_total_cents = sku.price_cents * item.quantity

    if item.save
      cart.update!(currency: sku.currency) if cart.currency != sku.currency
      cart.recalculate!
      render json: { cart: cart_json(cart.reload) }
    else
      Rails.logger.warn("[CART_ITEMS] Update failed for cart=#{cart.cart_id} sku=#{sku.sku_id} quantity=#{item.quantity}: #{item.errors.full_messages.join(', ')}")
      render_errors(item)
    end
  end

  def destroy
    require_scope("commerce:cart")

    cart = find_cart
    return if ensure_cart_owner(cart)

    sku = ::CommerceSku.find_by!(sku_id: params[:sku_id])
    cart.commerce_cart_items.find_by(commerce_sku: sku)&.destroy!

    render json: { cart: cart_json(cart.reload) }
  end
end
