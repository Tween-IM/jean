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
end
