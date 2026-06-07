# frozen_string_literal: true

class Api::V1::Commerce::OrdersController < Api::V1::Commerce::BaseController
  def index
    require_scope("commerce:orders")

    orders = ::CommerceOrder
      .where(buyer_user_id: @current_user.matrix_user_id)
      .or(::CommerceOrder.where(commerce_merchant: ::CommerceMerchant.where(owner_user_id: @current_user.matrix_user_id)))
      .order(created_at: :desc)
      .limit(limit_param(default: 20, max: 100))

    render json: {
      orders: orders.map { |o| order_json(o, detail: :public) }
    }
  end

  def show
    require_scope("commerce:orders")

    order = find_order
    if order.buyer_user_id == @current_user.matrix_user_id || order.commerce_merchant.owner_user_id == @current_user.matrix_user_id
      return render json: { order: order_json(order, detail: :full) }
    end

    render json: { error: "forbidden", message: "Order belongs to another account" }, status: :forbidden
  end

  def cancel
    require_scope("commerce:orders")

    order = find_order
    if order.buyer_user_id != @current_user.matrix_user_id
      return render json: { error: "forbidden", message: "Not your order" }, status: :forbidden
    end

    unless order.status.in?(%w[pending_payment paid processing])
      return render json: { error: "invalid_state", message: "Order cannot be cancelled in current state" }, status: :unprocessable_entity
    end

    order.update!(status: "cancelled", fulfillment_status: "not_required")
    # TODO: trigger refund if already paid

    render json: { order: order_json(order, detail: :full) }
  end

  private

  def limit_param(default:, max:)
    [ (params[:limit] || default).to_i, max ].min
  end
end
