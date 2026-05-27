class Api::V1::Commerce::RefundsController < Api::V1::Commerce::BaseController
  def create
    require_scope("commerce:merchant")

    order = find_order
    return if ensure_merchant_owner(order.commerce_merchant)

    refund = refund_params.to_h
    order.update!(
      status: refund["amount_cents"].to_i >= order.total_cents ? "refunded" : "partially_refunded",
      metadata: order.metadata.merge("refunds" => Array(order.metadata["refunds"]) + [ refund.merge("created_at" => Time.current.iso8601) ])
    )

    render json: { order: order_json(order) }, status: :created
  end

  private

  def refund_params
    params.require(:refund).permit(:amount_cents, :reason, metadata: {})
  end
end
