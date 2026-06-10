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

    # If already paid, trigger wallet refund before marking cancelled
    if order.status == "paid" && order.payment_id.present?
      begin
        refund_response = WalletService.refund_payment(
          order.payment_id,
          order.total_cents / 100.0,
          order.currency,
          "buyer_cancelled",
          @tep_token
        )

        if refund_response.is_a?(Hash) && (refund_response["refund_id"] || refund_response[:refund_id] || refund_response["id"] || refund_response[:id])
          order.metadata["refunds"] ||= []
          order.metadata["refunds"] << {
            "amount_cents" => order.total_cents,
            "reason" => "buyer_cancelled",
            "created_at" => Time.current.iso8601,
            "processed_by" => @current_user.matrix_user_id
          }
          order.update!(status: "refunded")
        else
          Rails.logger.warn "[OrdersController] Refund failed for order #{order.order_id}: #{refund_response.inspect}"
          return render json: { error: "refund_failed", message: "Refund could not be processed. Please contact support." }, status: :unprocessable_entity
        end
      rescue WalletService::WalletError => e
        Rails.logger.error "[OrdersController] Wallet refund failed for order #{order.order_id}: #{e.message}"
        return render json: { error: "refund_failed", message: "Refund service error: #{e.message}" }, status: :unprocessable_entity
      end
    else
      order.update!(status: "cancelled", fulfillment_status: "not_required")
    end

    ::Commerce::InventoryService.restore!(order)
    order.update!(metadata: order.metadata.merge("inventory_restored" => true, "cancelled_reason" => "buyer_cancelled"))

    render json: { order: order_json(order, detail: :full) }
  end

  private

  def limit_param(default:, max:)
    [ (params[:limit] || default).to_i, max ].min
  end
end
