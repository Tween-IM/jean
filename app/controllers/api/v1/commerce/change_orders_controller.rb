# frozen_string_literal: true

class Api::V1::Commerce::ChangeOrdersController < Api::V1::Commerce::BaseController
  def create
    require_scope("commerce:write")

    order = find_order
    participant!(order)

    change_order = ::CommerceChangeOrder.create!(change_order_params.merge(
      commerce_order: order,
      proposer_user_id: @current_user.matrix_user_id,
      status: "proposed"
    ))

    render json: { change_order: change_order_json(change_order) }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render_errors(e.record)
  rescue ArgumentError => e
    render json: { error: "change_order_failed", message: e.message }, status: :unprocessable_entity
  end

  def index
    require_scope("commerce:read")

    order = find_order
    return if ensure_participant(order)

    render json: { change_orders: order.commerce_change_orders.map { |c| change_order_json(c) } }
  end

  def accept
    require_scope("commerce:write")

    change_order = find_change_order
    return if ensure_participant(change_order)

    unless change_order.status == "proposed"
      return render json: { error: "invalid_state", message: "Change order is not open" }, status: :unprocessable_entity
    end

    order = change_order.commerce_order
    delta = change_order.amount_delta_cents.to_i
    begin
      ActiveRecord::Base.transaction do
        change_order.update!(
          status: "accepted",
          accepted_by_user_id: @current_user.matrix_user_id,
          accepted_at: Time.current
        )

        order.update!(
          total_cents: [ order.total_cents + delta, 0 ].max,
          terms_version: order.terms_version + 1,
          metadata: order.metadata.merge("last_change_order" => change_order.change_order_id)
        )

        # A positive price delta on a protected order collects the extra funding
        # immediately via a protected-payment top-up (buyer wallet debit).
        collect_funding_delta!(order, delta) if delta.positive? && order.protected_payment_id.present?
      end
    rescue ProtectedCommerceService::Error => e
      Rails.logger.error "[ChangeOrder] funding delta failed for #{change_order.change_order_id}: #{e.message}"
      return render json: { error: "funding_failed",
                            message: "Could not collect the additional payment: #{e.message}" },
                     status: :unprocessable_entity
    end

    render json: { change_order: change_order_json(change_order.reload), order: order_json(order, detail: :full) }
  rescue ActiveRecord::RecordInvalid => e
    render_errors(e.record)
  end

  private

  def find_change_order
    ::CommerceChangeOrder.find_by!(change_order_id: params[:id])
  end

  def change_order_params
    params.require(:change_order).permit(
      :amount_delta_cents, scope_delta: {}, deadline_delta: {}
    ).to_h
  end

  def collect_funding_delta!(order, delta)
    payment = ProtectedCommerceService.get_payment(order.protected_payment_id)[:protected_payment] || {}
    gross = (payment[:gross_amount_cents] || (order.total_cents - delta)).to_i
    commission_total = payment[:commission_cents].to_i
    commission = if gross.positive?
                   (delta * commission_total / gross.to_f).round
                 else
                   0
                 end
    commission = [commission, delta].min
    seller_proceeds = delta - commission

    ProtectedCommerceService.top_up(
      order.protected_payment_id,
      amount_cents: delta,
      commission_cents: commission,
      seller_proceeds_cents: seller_proceeds,
      actor: @current_user.matrix_user_id
    )
  end

  def participant!(order)
    ensure_participant_raise(order)
  end

  def ensure_participant(change_order)
    order = change_order.commerce_order
    return false if participant?(order)

    render json: { error: "forbidden", message: "Not a participant on this order" }, status: :forbidden
    true
  end

  def ensure_participant_raise(order)
    return if participant?(order)

    raise ArgumentError, "Not a participant on this order"
  end

  def participant?(order)
    @current_user.matrix_user_id == order.buyer_user_id ||
      @current_user.matrix_user_id == order.commerce_merchant.owner_user_id
  end

  def change_order_json(change_order)
    {
      change_order_id: change_order.change_order_id,
      order_id: change_order.commerce_order.order_id,
      proposer_user_id: change_order.proposer_user_id,
      scope_delta: change_order.scope_delta,
      amount_delta_cents: change_order.amount_delta_cents,
      deadline_delta: change_order.deadline_delta,
      status: change_order.status,
      accepted_at: change_order.accepted_at,
      created_at: change_order.created_at
    }
  end
end
