# frozen_string_literal: true

# Consumes Tween Pay's transactional-outbox callbacks for protected payments.
#
# - Signature is verified with a shared HMAC secret (constant-time compare).
# - Delivery is idempotent: receipts are recorded by event_id before applying.
# - Applies authoritative Tween Pay state to the CommerceOrder and publishes
#   Matrix events. Never uses a Matrix event as proof of a financial result.
class Api::V1::Commerce::ProtectedCommerceCallbacksController < Api::V1::Commerce::BaseController
  skip_before_action :authenticate_tep_token

  before_action :verify_signature
  before_action :dedupe_event

  def tween_pay
    event_type = params[:event_type].to_s
    data = params[:data].is_a?(ActionController::Parameters) ? params[:data].to_unsafe_h : {}
    data = (data || {}).deep_symbolize_keys

    payment_id = data[:protected_payment_id] || params[:protected_payment_id]
    order = ::CommerceOrder.find_by(protected_payment_id: payment_id)

    unless order
      Rails.logger.warn "[ProtectedCommerceCallback] no order for protected payment #{payment_id} (#{event_type})"
      return head :ok
    end

    apply_event!(order, event_type, data)
    head :ok
  end

  private

  def apply_event!(order, event_type, data)
    case event_type
    when "protected_payment.funded"
      order.update!(status: "paid", protection_status: "active")
      publish_payment_event(order, "m.tween.commerce.payment.funded", data)
    when "protected_payment.release_scheduled"
      order.update!(metadata: order.metadata.merge("release_at" => data[:release_at]))
    when "protected_payment.released"
      order.update!(status: "fulfilled", protection_status: "completed",
                    metadata: order.metadata.merge("released_at" => Time.current.iso8601))
      publish_payment_event(order, "m.tween.commerce.payment.released", data)
    when "protected_payment.refunded"
      if data[:total_refunded_cents].to_i >= order.total_cents
        order.update!(status: "refunded", protection_status: "completed")
      else
        order.update!(status: "partially_refunded")
      end
      publish_payment_event(order, "m.tween.commerce.payment.refunded", data)
    when "protected_payment.disputed"
      order.update!(metadata: order.metadata.merge("disputed_at" => Time.current.iso8601))
      publish_payment_event(order, "m.tween.commerce.dispute.opened", data)
    when "protected_payment.resolved"
      order.update!(protection_status: "completed")
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[ProtectedCommerceCallback] failed to apply #{event_type} to #{order.order_id}: #{e.message}"
  end

  def publish_payment_event(order, event_type, data)
    conversation = ::CommerceConversation.find_by(conversation_id: order.metadata["conversation_id"])
    MatrixEventService.publish_protected_payment_event(
      event_type,
      protected_payment_id: order.protected_payment_id,
      order_id: order.order_id,
      status: data[:status] || order.protection_status,
      currency: order.currency,
      gross_amount_cents: data[:gross_amount_cents] || order.total_cents,
      released_amount_cents: data[:released_amount_cents] || 0,
      refunded_amount_cents: data[:refunded_amount_cents] || 0,
      room_id: conversation&.matrix_room_id
    )
  end

  def verify_signature
    secret = ENV.fetch("JEAN_CALLBACK_SECRET", "")
    return render_invalid_signature unless secret.present?

    signature = request.headers["X-Tween-Signature"]
    return render_invalid_signature if signature.blank?

    body = request.body.read
    request.body.rewind
    expected = "sha256=" + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, body)
    return if ActiveSupport::SecurityUtils.secure_compare(signature, expected)

    render_invalid_signature
  end

  def render_invalid_signature
    render json: { error: "unauthorized", message: "Invalid signature" }, status: :unauthorized
  end

  def dedupe_event
    event_id = params[:event_id] || request.headers["X-Tween-Event-ID"]
    return render json: { error: "missing_event_id" }, status: :bad_request if event_id.blank?

    @receipt = ::CommerceProtectedPaymentCallback.record!(
      event_id: event_id,
      event_type: params[:event_type].to_s,
      protected_payment_id: params.dig(:data, :protected_payment_id),
      payload: request.raw_post
    )
  end
end
