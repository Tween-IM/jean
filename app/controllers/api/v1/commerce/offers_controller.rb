# frozen_string_literal: true

class Api::V1::Commerce::OffersController < Api::V1::Commerce::BaseController
  before_action :find_conversation, only: %i[index create]
  before_action :find_offer, only: %i[counter accept decline]

  SERVICE = ::Commerce::OfferService.new

  def index
    require_scope("commerce:read")

    offers = @conversation.commerce_offers.order(created_at: :desc).limit(50)
    render json: { offers: offers.map { |offer| offer.offer_json(detail: :full) } }
  end

  def create
    require_scope("commerce:write")

    offer = SERVICE.create!(@conversation, @current_user.matrix_user_id, offer_params)
    publish_offer_event(offer, "m.tween.commerce.offer")
    render json: { offer: offer.offer_json(detail: :full) }, status: :created
  rescue ::Commerce::OfferService::Error => e
    render json: { error: "offer_failed", message: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render_errors(e.record)
  end

  def counter
    require_scope("commerce:write")

    offer = SERVICE.counter!(@offer, @current_user.matrix_user_id, offer_params)
    publish_offer_event(offer, "m.tween.commerce.offer.updated")
    render json: { offer: offer.offer_json(detail: :full) }, status: :created
  rescue ::Commerce::OfferService::Error => e
    render json: { error: "counteroffer_failed", message: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render_errors(e.record)
  end

  def accept
    require_scope("commerce:write")

    order = SERVICE.accept!(@offer, @current_user.matrix_user_id)
    publish_order_created(order)
    render json: { offer: @offer.reload.offer_json(detail: :full), order: order_json(order, detail: :full) }
  rescue ::Commerce::OfferService::NotRecipientError => e
    render json: { error: "forbidden", message: e.message }, status: :forbidden
  rescue ::Commerce::OfferService::ExpiredError => e
    render json: { error: "offer_expired", message: e.message }, status: :unprocessable_entity
  rescue ::Commerce::OfferService::InvalidStateError => e
    render json: { error: "invalid_state", message: e.message }, status: :unprocessable_entity
  rescue ::Commerce::OfferService::PaymentError => e
    render json: { error: "payment_failed", message: e.message }, status: :service_unavailable
  rescue ActiveRecord::RecordInvalid => e
    render_errors(e.record)
  end

  def decline
    require_scope("commerce:write")

    offer = SERVICE.decline!(@offer, @current_user.matrix_user_id)
    publish_offer_event(offer, "m.tween.commerce.offer.updated")
    render json: { offer: offer.offer_json(detail: :full) }
  rescue ::Commerce::OfferService::NotRecipientError => e
    render json: { error: "forbidden", message: e.message }, status: :forbidden
  rescue ::Commerce::OfferService::Error => e
    render json: { error: "decline_failed", message: e.message }, status: :unprocessable_entity
  end

  private

  def find_conversation
    @conversation = ::CommerceConversation.find_by!(conversation_id: params[:conversation_id])
  end

  def find_offer
    @offer = ::CommerceOffer.find_by!(offer_id: params[:offer_id] || params[:id])
  end

  def offer_params
    params.require(:offer).permit(
      :offer_type, :currency, :subtotal_cents, :delivery_fee_cents, :buyer_fee_cents,
      :discount_cents, :total_cents, :commission_cents, :seller_proceeds_cents,
      :commission_rate, :expires_at, terms: {}
    ).to_h
  end

  def publish_offer_event(offer, event_type)
    room_id = @conversation.matrix_room_id
    return unless room_id

    MatrixEventService.publish_offer_event(
      {
        offer_id: offer.offer_id,
        conversation_id: offer.conversation_id,
        offer_type: offer.offer_type,
        version: offer.version,
        status: offer.status,
        currency: offer.currency,
        total_cents: offer.total_cents,
        seller_proceeds_cents: offer.seller_proceeds_cents,
        expires_at: offer.expires_at,
        room_id: room_id
      },
      event_type: event_type
    )
  end

  def publish_order_created(order)
    conversation = @offer ? @offer.commerce_conversation : @conversation
    MatrixEventService.publish_order_created(
      order_id: order.order_id,
      payment_id: order.payment_id,
      merchant_id: order.commerce_merchant.merchant_id,
      buyer_user_id: order.buyer_user_id,
      status: order.status,
      total: { amount: order.total_cents.to_s, currency: order.currency },
      room_id: conversation&.matrix_room_id
    )
  end
end
