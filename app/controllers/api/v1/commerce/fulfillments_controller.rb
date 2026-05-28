# frozen_string_literal: true

class Api::V1::Commerce::FulfillmentsController < Api::V1::Commerce::BaseController
  def create
    require_scope("commerce:merchant")

    order = find_order
    return if ensure_merchant_owner(order.commerce_merchant)

    order.update!(
      fulfillment_status: fulfillment_params[:fulfillment_status].presence || "fulfilled",
      status: fulfillment_params[:status].presence || order.status,
      metadata: order.metadata.merge("fulfillment" => fulfillment_params.to_h.merge("updated_by" => @current_user.matrix_user_id))
    )

    deliver_order_webhook(order, "commerce.fulfillment.updated")
    emit_order_updated(order)

    render json: { order: order_json(order) }
  end

  private

  def fulfillment_params
    return {} if params[:fulfillment].blank?

    params.require(:fulfillment).permit(:fulfillment_status, :status, :carrier, :tracking_number, :tracking_url, metadata: {})
  end

  def deliver_order_webhook(order, event_type)
    webhook_url = order.commerce_merchant.webhook_url
    return unless webhook_url

    payload = {
      order_id: order.order_id,
      checkout_id: order.metadata["checkout_id"],
      payment_id: order.payment_id,
      merchant_id: order.commerce_merchant.merchant_id,
      buyer_user_id: order.buyer_user_id,
      status: order.status,
      fulfillment_status: order.fulfillment_status
    }

    WebhookService.new.deliver(event_type: event_type, payload: payload, webhook_url: webhook_url)
  end

  def emit_order_updated(order)
    MatrixEventService.publish_order_updated(
      order_id: order.order_id,
      buyer_user_id: order.buyer_user_id,
      status: order.status,
      fulfillment_status: order.fulfillment_status
    )
  end
end
