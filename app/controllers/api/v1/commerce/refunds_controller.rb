# frozen_string_literal: true

class Api::V1::Commerce::RefundsController < Api::V1::Commerce::BaseController
  def create
    require_scope("commerce:merchant")

    order = find_order
    return if ensure_merchant_owner(order.commerce_merchant)

    result = ::Commerce::RefundService.new(tep_token: @tep_token).call(
      order: order,
      amount_cents: refund_params[:amount_cents],
      reason: refund_params[:reason].presence || "merchant_refund",
      actor: @current_user.matrix_user_id,
      metadata: refund_params[:metadata].to_h
    )

    render json: { order: order_json(result.order) }, status: :created
  rescue ::Commerce::RefundService::UnsupportedError => e
    render json: { error: "refund_not_supported", message: e.message }, status: :unprocessable_entity
  rescue ::Commerce::RefundService::Error => e
    render json: { error: "refund_failed", message: e.message }, status: :unprocessable_entity
  end

  private

  def refund_params
    params.require(:refund).permit(:amount_cents, :amount, :reason, metadata: {})
  end
end
