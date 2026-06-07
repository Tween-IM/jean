# frozen_string_literal: true

class Api::V1::Commerce::CartsController < Api::V1::Commerce::BaseController
  def create
    require_scope("commerce:cart")

    merchant = find_merchant
    cart = merchant.commerce_carts.create!(
      buyer_user_id: @current_user.matrix_user_id,
      currency: params[:currency].presence || "USD",
      status: "active"
    )

    render json: { cart: cart_json(cart) }, status: :created
  end

  def show
    require_scope("commerce:cart")

    cart = find_cart
    return if ensure_cart_owner(cart)

    render json: { cart: cart_json(cart) }
  end

  def shipping_quotes
    require_scope("commerce:cart")

    cart = find_cart
    return if ensure_cart_owner(cart)

    result = Commerce::ShippingCalculatorService.calculate_for_cart(
      cart: cart,
      destination_country: params[:country].presence || "NG",
      destination_state: params[:state].presence
    )

    render json: {
      shipping_quotes: result[:options].filter_map do |option|
        next if option[:rate_cents].nil?

        {
          shipping_profile_id: option[:profile_id],
          name: option[:name],
          rate_cents: option[:rate_cents],
          currency: option[:currency],
          delivery_days: option[:delivery_days]
        }
      end
    }
  end
end
