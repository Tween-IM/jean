# frozen_string_literal: true

class Api::V1::Commerce::OrdersController < Api::V1::Commerce::BaseController
  def show
    require_scope("commerce:orders")

    order = find_order
    if order.buyer_user_id == @current_user.matrix_user_id || order.commerce_merchant.owner_user_id == @current_user.matrix_user_id
      return render json: { order: order_json(order) }
    end

    render json: { error: "forbidden", message: "Order belongs to another account" }, status: :forbidden
  end
end
