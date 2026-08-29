# frozen_string_literal: true

class Api::V1::Commerce::OrdersController < Api::V1::Commerce::BaseController
  def index
    require_scope("commerce:orders")

    orders = ::CommerceOrder
      .where(buyer_user_id: @current_user.matrix_user_id)
      .or(::CommerceOrder.where(commerce_merchant: ::CommerceMerchant.where(owner_user_id: @current_user.matrix_user_id)))
      .order(created_at: :desc)
      .limit(limit_param(default: 20, max: 100))

    render json: {
      orders: orders.map { |o| order_json(o, detail: :public) }
    }
  end

  def show
    require_scope("commerce:orders")

    order = find_order
    if order.buyer_user_id == @current_user.matrix_user_id || order.commerce_merchant.owner_user_id == @current_user.matrix_user_id
      return render json: { order: order_json(order, detail: :full) }
    end

    render json: { error: "forbidden", message: "Order belongs to another account" }, status: :forbidden
  end

  def cancel
    require_scope("commerce:orders")

    order = find_order
    if order.buyer_user_id != @current_user.matrix_user_id
      return render json: { error: "forbidden", message: "Not your order" }, status: :forbidden
    end

    unless order.status.in?(%w[pending_payment paid processing])
      return render json: { error: "invalid_state", message: "Order cannot be cancelled in current state" }, status: :unprocessable_entity
    end

    # If already paid, trigger wallet refund before marking cancelled
    if order.status == "paid" && order.payment_id.present?
      begin
        refund_response = WalletService.refund_payment(
          order.payment_id,
          order.total_cents / 100.0,
          order.currency,
          "buyer_cancelled",
          @tep_token
        )

        if refund_response.is_a?(Hash) && (refund_response["refund_id"] || refund_response[:refund_id] || refund_response["id"] || refund_response[:id])
          order.metadata["refunds"] ||= []
          order.metadata["refunds"] << {
            "amount_cents" => order.total_cents,
            "reason" => "buyer_cancelled",
            "created_at" => Time.current.iso8601,
            "processed_by" => @current_user.matrix_user_id
          }
          order.update!(status: "refunded")
        else
          Rails.logger.warn "[OrdersController] Refund failed for order #{order.order_id}: #{refund_response.inspect}"
          return render json: { error: "refund_failed", message: "Refund could not be processed. Please contact support." }, status: :unprocessable_entity
        end
      rescue WalletService::WalletError => e
        Rails.logger.error "[OrdersController] Wallet refund failed for order #{order.order_id}: #{e.message}"
        return render json: { error: "refund_failed", message: "Refund service error: #{e.message}" }, status: :unprocessable_entity
      end
    else
      order.update!(status: "cancelled", fulfillment_status: "not_required")
    end

    ::Commerce::InventoryService.restore!(order)
    order.update!(metadata: order.metadata.merge("inventory_restored" => true, "cancelled_reason" => "buyer_cancelled"))

    render json: { order: order_json(order, detail: :full) }
  end

  def fund
    require_scope("commerce:orders")

    order = find_order
    if order.buyer_user_id != @current_user.matrix_user_id
      return render json: { error: "forbidden", message: "Not your order" }, status: :forbidden
    end

    unless order.protected_payment_id.present?
      return render json: { error: "invalid_state", message: "Order is not protected" }, status: :unprocessable_entity
    end
    unless order.status == "pending_payment"
      return render json: { error: "invalid_state", message: "Order is not awaiting payment" }, status: :unprocessable_entity
    end

    response = ProtectedCommerceService.fund(
      order.protected_payment_id,
      actor: @current_user.matrix_user_id
    )
    order.update!(
      status: "paid",
      protection_status: "active",
      metadata: order.metadata.merge("funded_at" => Time.current.iso8601)
    )
    CommerceNotifier.payment_funded(order)
    publish_payment_event(order, "m.tween.commerce.payment.funded")

    render json: { order: order_json(order.reload, detail: :full), protected_payment: response[:protected_payment] }
  rescue ProtectedCommerceService::Error => e
    error_code = e.code&.to_s&.downcase
    message = error_code == "insufficient_funds" ? "Insufficient funds. Please top up your wallet." : e.message
    render json: { error: error_code || "payment_failed", message: message }, status: :payment_required
  end

  def mark_delivered
    require_scope("commerce:orders")

    order = find_order
    fulfillment = ::Commerce::FulfillmentService.new.mark_delivered!(
      order,
      @current_user.matrix_user_id,
      note: params[:note]
    )

    CommerceNotifier.delivery_declared(order)
    publish_fulfilment_event(fulfillment, order)
    render json: { order: order_json(order.reload, detail: :full), fulfillment: fulfillment_json(fulfillment) }
  rescue ::Commerce::FulfillmentService::NotAuthorizedError => e
    render json: { error: "forbidden", message: e.message }, status: :forbidden
  rescue ::Commerce::FulfillmentService::Error => e
    render json: { error: "fulfilment_failed", message: e.message }, status: :unprocessable_entity
  end

  def confirm_delivery
    require_scope("commerce:orders")

    order = find_order
    result = ::Commerce::FulfillmentService.new.confirm_delivery!(order, @current_user.matrix_user_id)

    fulfillment = result[:fulfillment]
    publish_fulfilment_event(fulfillment, order)
    publish_delivery_confirmed(order, result[:inspection_deadline])

    render json: {
      order: order_json(order.reload, detail: :full),
      fulfillment: fulfillment_json(fulfillment),
      inspection_deadline: result[:inspection_deadline]
    }
  rescue ::Commerce::FulfillmentService::NotAuthorizedError => e
    render json: { error: "forbidden", message: e.message }, status: :forbidden
  rescue ::Commerce::FulfillmentService::Error => e
    render json: { error: "fulfilment_failed", message: e.message }, status: :unprocessable_entity
  end

  def service_submission
    require_scope("commerce:orders")

    order = find_order
    fulfillment = ::Commerce::FulfillmentService.new.submit_service!(
      order,
      @current_user.matrix_user_id,
      evidence: submission_params[:evidence] || []
    )

    publish_fulfilment_event(fulfillment, order)
    render json: { order: order_json(order.reload, detail: :full), fulfillment: fulfillment_json(fulfillment) }
  rescue ::Commerce::FulfillmentService::NotAuthorizedError => e
    render json: { error: "forbidden", message: e.message }, status: :forbidden
  rescue ::Commerce::FulfillmentService::Error => e
    render json: { error: "fulfilment_failed", message: e.message }, status: :unprocessable_entity
  end

  def issue_pickup_code
    require_scope("commerce:orders")

    order = find_order
    code = ::Commerce::FulfillmentService.new.issue_pickup_code!(order, @current_user.matrix_user_id)
    render json: { pickup_code: code, expires_in_minutes: CommercePickupCode::CODE_TTL_MINUTES }
  rescue ::Commerce::FulfillmentService::NotAuthorizedError => e
    render json: { error: "forbidden", message: e.message }, status: :forbidden
  rescue ::Commerce::FulfillmentService::Error => e
    render json: { error: "pickup_failed", message: e.message }, status: :unprocessable_entity
  end

  def confirm_pickup
    require_scope("commerce:orders")

    order = find_order
    code = params[:code].presence
    return render json: { error: "missing_code", message: "Pickup code is required" }, status: :bad_request if code.blank?

    fulfillment = ::Commerce::FulfillmentService.new.confirm_pickup!(order, @current_user.matrix_user_id, code)
    publish_fulfilment_event(fulfillment, order)
    render json: { order: order_json(order.reload, detail: :full), fulfillment: fulfillment_json(fulfillment) }
  rescue ::Commerce::FulfillmentService::NotAuthorizedError => e
    render json: { error: "forbidden", message: e.message }, status: :forbidden
  rescue CommercePickupCode::InvalidCodeError => e
    render json: { error: "invalid_code", message: e.message }, status: :unprocessable_entity
  rescue CommercePickupCode::ExpiredCodeError => e
    render json: { error: "expired_code", message: e.message }, status: :unprocessable_entity
  rescue ::Commerce::FulfillmentService::Error => e
    render json: { error: "pickup_failed", message: e.message }, status: :unprocessable_entity
  end

  private

  def limit_param(default:, max:)
    [ (params[:limit] || default).to_i, max ].min
  end

  def submission_params
    params.require(:submission).permit(evidence: [ :media_type, :url, :caption ])
  rescue ActionController::ParameterMissing
    {}
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
      tracking_number: fulfillment.tracking_number,
      room_id: order.metadata["conversation_id"].presence && conversation_room(order)
    )
  end

  def publish_delivery_confirmed(order, inspection_deadline)
    MatrixEventService.publish_delivery_confirmed(
      order_id: order.order_id,
      fulfillment_id: order.commerce_fulfillments.latest_first.first&.fulfillment_id,
      inspection_deadline: inspection_deadline.iso8601,
      room_id: conversation_room(order)
    )
  end

  def conversation_room(order)
    conversation = ::CommerceConversation.find_by(conversation_id: order.metadata["conversation_id"])
    conversation&.matrix_room_id
  end

  def publish_payment_event(order, event_type)
    MatrixEventService.publish_protected_payment_event(
      event_type,
      protected_payment_id: order.protected_payment_id,
      order_id: order.order_id,
      status: order.protection_status,
      currency: order.currency,
      gross_amount_cents: order.total_cents,
      room_id: conversation_room(order)
    )
  end
end
