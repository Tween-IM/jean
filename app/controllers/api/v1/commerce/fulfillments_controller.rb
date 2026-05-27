class Api::V1::Commerce::FulfillmentsController < Api::V1::Commerce::BaseController
  def create
    require_scope("commerce:merchant")

    order = find_order
    return if ensure_merchant_owner(order.commerce_merchant)

    order.update!(
      fulfillment_status: params[:fulfillment_status].presence || "fulfilled",
      status: params[:status].presence || "fulfilled",
      metadata: order.metadata.merge("fulfillment" => fulfillment_params.to_h)
    )

    render json: { order: order_json(order) }
  end

  private

  def fulfillment_params
    return {} if params[:fulfillment].blank?

    params.require(:fulfillment).permit(:carrier, :tracking_number, :tracking_url, metadata: {})
  end
end
