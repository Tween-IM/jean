class Api::V1::Commerce::CartItemsController < Api::V1::Commerce::BaseController
  def update
    require_scope("commerce:cart")

    cart = find_cart
    return if ensure_cart_owner(cart)

    sku = ::CommerceSku.find_by!(sku_id: params[:sku_id])
    item = cart.commerce_cart_items.find_or_initialize_by(commerce_sku: sku)
    item.quantity = params.require(:quantity)

    if item.save
      render json: { cart: cart_json(cart.reload) }
    else
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
