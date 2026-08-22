# frozen_string_literal: true

class Api::V1::Commerce::DisputesController < Api::V1::Commerce::BaseController
  DISPUTE_REASONS = %w[
    item_not_received materially_different damaged_or_counterfeit prohibited_item
    wrong_quantity service_not_started service_incomplete deficient_workmanship
    unapproved_charges
  ].freeze

  def create
    require_scope("commerce:write")

    order = find_order
    return if ensure_buyer(order)

    reason = dispute_params[:reason]
    unless DISPUTE_REASONS.include?(reason)
      return render json: { error: "invalid_reason", message: "Unsupported dispute reason" }, status: :unprocessable_entity
    end

    dispute = nil
    ActiveRecord::Base.transaction do
      dispute = ::CommerceDispute.create!(
        commerce_order: order,
        protected_payment_id: order.protected_payment_id,
        opened_by_user_id: @current_user.matrix_user_id,
        reason: reason,
        description: dispute_params[:description],
        status: "open",
        snapshots: dispute_snapshots(order)
      )
      order.update!(metadata: order.metadata.merge("open_dispute_id" => dispute.dispute_id))
    end

    # Freeze release in Tween Pay — opening a dispute atomically cancels any
    # scheduled release.
    begin
      ProtectedCommerceService.open_dispute(
        order.protected_payment_id,
        reason: reason,
        actor: @current_user.matrix_user_id
      )
    rescue ProtectedCommerceService::Error => e
      Rails.logger.warn "[Disputes] Failed to freeze payment #{order.protected_payment_id}: #{e.message}"
    end

    publish_dispute_opened(dispute, order)
    render json: { dispute: dispute_json(dispute) }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render_errors(e.record)
  end

  def show
    require_scope("commerce:read")

    dispute = find_dispute
    order = dispute.commerce_order
    return if ensure_participant(order)

    render json: { dispute: dispute_json(dispute, detail: :full) }
  end

  def evidence
    require_scope("commerce:write")

    dispute = find_dispute
    order = dispute.commerce_order
    return if ensure_participant(order)
    unless dispute.open?
      return render json: { error: "invalid_state", message: "Dispute is closed" }, status: :unprocessable_entity
    end

    item = dispute.evidence.create!(evidence_params.merge(
      uploaded_by_user_id: @current_user.matrix_user_id
    ))
    render json: { evidence: evidence_json(item) }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render_errors(e.record)
  end

  private

  def find_dispute
    ::CommerceDispute.find_by!(dispute_id: params[:id])
  end

  def dispute_params
    return {} if params[:dispute].blank?

    params.require(:dispute).permit(:reason, :description)
  end

  def evidence_params
    params.require(:evidence).permit(:media_type, :url, :content_type, :size_bytes, :caption).to_h
  end

  def ensure_buyer(order)
    return false if order.buyer_user_id == @current_user.matrix_user_id

    render json: { error: "forbidden", message: "Only the buyer can open a dispute" }, status: :forbidden
    true
  end

  def ensure_participant(order)
    return false if order.buyer_user_id == @current_user.matrix_user_id ||
                    order.commerce_merchant.owner_user_id == @current_user.matrix_user_id

    render json: { error: "forbidden", message: "Not a participant on this order" }, status: :forbidden
    true
  end

  def dispute_snapshots(order)
    {
      order: {
        status: order.status,
        protection_status: order.protection_status,
        total_cents: order.total_cents,
        currency: order.currency,
        items: order.commerce_order_items.map(&:attributes)
      },
      accepted_offer_id: order.accepted_offer_id,
      protected_payment_id: order.protected_payment_id,
      captured_at: Time.current.iso8601
    }
  end

  def dispute_json(dispute, detail: :public)
    base = {
      dispute_id: dispute.dispute_id,
      order_id: dispute.commerce_order.order_id,
      reason: dispute.reason,
      description: dispute.description,
      status: dispute.status,
      opened_by_user_id: dispute.opened_by_user_id,
      opened_at: dispute.opened_at,
      resolution: dispute.resolution,
      evidence: dispute.evidence.map { |e| evidence_json(e) }
    }

    base.merge!(snapshots: dispute.snapshots) if detail == :full
    base
  end

  def evidence_json(item)
    {
      evidence_id: item.evidence_id,
      media_type: item.media_type,
      url: item.url,
      content_type: item.content_type,
      size_bytes: item.size_bytes,
      caption: item.caption,
      uploaded_by_user_id: item.uploaded_by_user_id,
      uploaded_at: item.uploaded_at
    }
  end

  def publish_dispute_opened(dispute, order)
    conversation = ::CommerceConversation.find_by(conversation_id: order.metadata["conversation_id"])
    MatrixEventService.publish_dispute_opened(
      dispute_id: dispute.dispute_id,
      order_id: order.order_id,
      reason: dispute.reason,
      status: dispute.status,
      room_id: conversation&.matrix_room_id
    )
  end
end
