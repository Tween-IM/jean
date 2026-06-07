# frozen_string_literal: true

class Api::V1::Commerce::FulfillmentsController < Api::V1::Commerce::BaseController
  def create
    require_scope("commerce:merchant")

    order = find_order
    return if ensure_merchant_owner(order.commerce_merchant)

    # Build tracking info
    tracking = {
      carrier: fulfillment_params[:carrier],
      tracking_number: fulfillment_params[:tracking_number],
      tracking_url: fulfillment_params[:tracking_url],
      shipped_at: Time.current.iso8601,
      updated_by: @current_user.matrix_user_id
    }.compact

    existing_fulfillments = order.metadata["fulfillments"] || []
    existing_fulfillments << tracking

    new_fulfillment_status = fulfillment_params[:fulfillment_status].presence || "fulfilled"
    new_status = fulfillment_params[:status].presence || order.status

    # If partial shipment, set partial status
    if fulfillment_params[:line_items].present?
      new_fulfillment_status = "partially_fulfilled" if new_fulfillment_status == "fulfilled" && existing_fulfillments.size > 1
    end

    order.update!(
      fulfillment_status: new_fulfillment_status,
      status: new_status,
      metadata: order.metadata.merge(
        "fulfillments" => existing_fulfillments,
        "last_fulfillment" => tracking
      )
    )

    deliver_order_webhook(order, "commerce.fulfillment.updated")
    emit_order_updated(order)

    render json: { order: order_json(order, detail: :full) }
  end

  private

  def fulfillment_params
    return {} if params[:fulfillment].blank?

    params.require(:fulfillment).permit(
      :fulfillment_status, :status, :carrier, :tracking_number, :tracking_url,
      line_items: [], metadata: {}
    )
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
      fulfillment_status: order.fulfillment_status,
      tracking: order.metadata["last_fulfillment"]
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
