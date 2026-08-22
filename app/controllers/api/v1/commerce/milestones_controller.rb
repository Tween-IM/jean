# frozen_string_literal: true

# Service milestones: separately reviewable and releasable portions of a
# service order. Release posts a partial release to Tween Pay.
class Api::V1::Commerce::MilestonesController < Api::V1::Commerce::BaseController
  SERVICE = ::Commerce::FulfillmentService.new

  def index
    require_scope("commerce:read")

    order = find_order
    return if ensure_participant(order)

    render json: { milestones: order.commerce_service_milestones.map { |m| milestone_json(m) } }
  end

  def create
    require_scope("commerce:write")

    order = find_order
    return if ensure_participant(order)

    milestone = SERVICE.add_milestone!(order, @current_user.matrix_user_id, milestone_params)
    render json: { milestone: milestone_json(milestone) }, status: :created
  rescue ::Commerce::FulfillmentService::Error => e
    render json: { error: "milestone_failed", message: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render_errors(e.record)
  end

  def submit
    require_scope("commerce:write")

    order = find_order
    return if ensure_participant(order)

    milestone = find_milestone(order)
    milestone = SERVICE.submit_milestone!(
      order, @current_user.matrix_user_id, milestone,
      evidence: submission_params[:evidence] || []
    )
    render json: { milestone: milestone_json(milestone) }
  rescue ::Commerce::FulfillmentService::Error => e
    render json: { error: "milestone_failed", message: e.message }, status: :unprocessable_entity
  end

  def accept
    require_scope("commerce:write")

    order = find_order
    return if ensure_participant(order)

    milestone = find_milestone(order)
    milestone = SERVICE.accept_milestone!(order, @current_user.matrix_user_id, milestone)
    render json: { milestone: milestone_json(milestone) }
  rescue ::Commerce::FulfillmentService::Error => e
    render json: { error: "milestone_failed", message: e.message }, status: :unprocessable_entity
  end

  private

  def find_order
    ::CommerceOrder.find_by!(order_id: params[:order_id] || params[:id])
  end

  def find_milestone(order)
    order.commerce_service_milestones.find_by!(milestone_id: params[:milestone_id] || params[:id])
  end

  def milestone_params
    params.require(:milestone).permit(
      :title, :description, :amount_cents, :scheduled_at
    ).to_h
  end

  def submission_params
    params.require(:submission).permit(evidence: [ :media_type, :url, :caption ])
  rescue ActionController::ParameterMissing
    {}
  end

  def ensure_participant(order)
    return false if order.buyer_user_id == @current_user.matrix_user_id ||
                    order.commerce_merchant.owner_user_id == @current_user.matrix_user_id

    render json: { error: "forbidden", message: "Not a participant on this order" }, status: :forbidden
    true
  end

  def milestone_json(milestone)
    {
      milestone_id: milestone.milestone_id,
      order_id: milestone.commerce_order.order_id,
      title: milestone.title,
      description: milestone.description,
      amount_cents: milestone.amount_cents,
      currency: milestone.currency,
      status: milestone.status,
      scheduled_at: milestone.scheduled_at,
      completed_at: milestone.completed_at,
      released_at: milestone.released_at,
      evidence: milestone.evidence
    }
  end
end
