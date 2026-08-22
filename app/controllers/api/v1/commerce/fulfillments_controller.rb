# frozen_string_literal: true

class Api::V1::Commerce::FulfillmentsController < Api::V1::Commerce::BaseController
  def create
    require_scope("commerce:merchant")

    order = find_order
    return if ensure_merchant_owner(order.commerce_merchant)

    fulfillment = ::Commerce::FulfillmentService.new.create_shipment!(
      order, @current_user.matrix_user_id, fulfillment_params
    )

    publish_fulfilment_event(fulfillment, order)
    deliver_order_webhook(order, "commerce.fulfillment.updated")

    render json: {
      order: order_json(order.reload, detail: :full),
      fulfillment: fulfillment_json(fulfillment)
    }
  rescue ::Commerce::FulfillmentService::Error => e
    render json: { error: "fulfilment_failed", message: e.message }, status: :unprocessable_entity
  end

  private

  def fulfillment_params
    return {} if params[:fulfillment].blank?

    params.require(:fulfillment).permit(
      :kind, :carrier, :tracking_number, :tracking_url, :status, metadata: {}
    )
  end

  def fulfillment_json(fulfillment)
    {
      fulfillment_id: fulfillment.fulfillment_id,
      kind: fulfillment.kind,
      status: fulfillment.status,
      provider: fulfillment.provider,
      tracking_number: fulfillment.tracking_number,
      tracking_url: fulfillment.tracking_url,
      shipped_at: fulfillment.shipped_at,
      delivered_at: fulfillment.delivered_at,
      accepted_at: fulfillment.accepted_at
    }
  end

  def publish_fulfilment_event(fulfillment, order)
    MatrixEventService.publish_fulfilment_updated(
      fulfillment_id: fulfillment.fulfillment_id,
      order_id: order.order_id,
      kind: fulfillment.kind,
      status: fulfillment.status,
      tracking_number: fulfillment.tracking_number
    )
  end

  def deliver_order_webhook(order, event_type)
    webhook_url = order.commerce_merchant.webhook_url
    return unless webhook_url

    payload = {
      order_id: order.order_id,
      checkout_id: order.metadata["checkout_id"],
      payment_id: order.payment_id,
      protected_payment_id: order.protected_payment_id,
      merchant_id: order.commerce_merchant.merchant_id,
      buyer_user_id: order.buyer_user_id,
      status: order.status,
      protection_status: order.protection_status,
      fulfillment_status: order.fulfillment_status,
      fulfillment: order.commerce_fulfillments.latest_first.first&.attributes&.slice(
        "fulfillment_id", "kind", "status", "tracking_number", "tracking_url"
      )
    }

    WebhookService.new.deliver(event_type: event_type, payload: payload, webhook_url: webhook_url)
  end
end
