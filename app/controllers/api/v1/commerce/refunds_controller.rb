# frozen_string_literal: true

class Api::V1::Commerce::RefundsController < Api::V1::Commerce::BaseController
  def create
    require_scope("commerce:merchant")

    order = find_order
    return if ensure_merchant_owner(order.commerce_merchant)

    refund_data = refund_params.to_h
    is_full_refund = refund_data["amount_cents"].to_i >= order.total_cents

    # Attempt wallet refund before updating local state
    if order.payment_id.present? && order.status == "paid"
      begin
        refund_response = WalletService.refund_payment(
          order.payment_id,
          refund_data["amount_cents"] / 100.0,
          order.currency,
          refund_data["reason"] || "merchant_refund",
          @tep_token
        )

        unless refund_response.is_a?(Hash) && (refund_response["refund_id"] || refund_response[:refund_id] || refund_response["id"] || refund_response[:id])
          Rails.logger.warn "[RefundsController] Wallet refund failed for order #{order.order_id}: #{refund_response.inspect}"
          return render json: { error: "refund_failed", message: "Wallet refund could not be processed. Please try again." }, status: :unprocessable_entity
        end
      rescue WalletService::WalletError => e
        Rails.logger.error "[RefundsController] Wallet refund error for order #{order.order_id}: #{e.message}"
        return render json: { error: "refund_failed", message: "Wallet service error: #{e.message}" }, status: :unprocessable_entity
      end
    end

    if is_full_refund
      ::Commerce::InventoryService.restore!(order)
      order.update!(metadata: order.metadata.merge("inventory_restored" => true, "cancelled_reason" => "refunded"))
    end

    order.update!(
      status: is_full_refund ? "refunded" : "partially_refunded",
      metadata: order.metadata.merge("refunds" => Array(order.metadata["refunds"]) + [ refund_data.merge("created_at" => Time.current.iso8601, "processed_by" => @current_user.matrix_user_id) ])
    )

    emit_refund_updated(order, refund_data)
    deliver_refund_webhook(order, "commerce.refund.updated")

    render json: { order: order_json(order) }, status: :created
  end

  private

  def refund_params
    params.require(:refund).permit(:amount_cents, :amount, :reason, metadata: {})
  end

  def emit_refund_updated(order, refund_data)
    MatrixEventService.publish_refund_updated(
      refund_id: "ref_#{SecureRandom.alphanumeric(12)}",
      order_id: order.order_id,
      buyer_user_id: order.buyer_user_id,
      amount: { amount: refund_data["amount_cents"] || order.total_cents.to_s, currency: order.currency },
      status: order.status,
      reason: refund_data["reason"]
    )
  end

  def deliver_refund_webhook(order, event_type)
    webhook_url = order.commerce_merchant.webhook_url
    return unless webhook_url

    payload = {
      order_id: order.order_id,
      checkout_id: order.metadata["checkout_id"],
      payment_id: order.payment_id,
      merchant_id: order.commerce_merchant.merchant_id,
      buyer_user_id: order.buyer_user_id,
      status: order.status
    }

    WebhookService.new.deliver(event_type: event_type, payload: payload, webhook_url: webhook_url)
  end
end
