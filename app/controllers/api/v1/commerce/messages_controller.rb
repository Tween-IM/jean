# frozen_string_literal: true

class Api::V1::Commerce::MessagesController < Api::V1::Commerce::BaseController
  def create
    require_scope("commerce:orders")

    order = ::CommerceOrder.find_by!(order_id: params[:order_id])

    # Verify ownership: must be buyer OR merchant owner
    unless order.buyer_user_id == @current_user.matrix_user_id ||
           order.commerce_merchant.owner_user_id == @current_user.matrix_user_id
      return render json: { error: "forbidden", message: "Not authorized to message on this order" }, status: :forbidden
    end

    # Only allow messaging on paid/processing/fulfilled orders
    unless order.status.in?(%w[paid processing fulfilled partially_fulfilled])
      return render json: { error: "invalid_order", message: "Messaging available after payment" }, status: :forbidden
    end

    # Return existing room if already created
    room_id = order.metadata&.dig("commerce_room_id")
    if room_id.present?
      return render json: {
        room_id: room_id,
        buyer_label: buyer_label(order),
        seller_label: seller_label(order),
        existing: true
      }
    end

    # Create relay room via bot
    room_id = CommerceRelayService.create_order_room(order)
    order.metadata_will_change!
    order.metadata["commerce_room_id"] = room_id
    order.save!

    render json: {
      room_id: room_id,
      buyer_label: buyer_label(order),
      seller_label: seller_label(order),
      existing: false
    }, status: :created
  end

  private

  def buyer_label(order)
    profile = SocialCreatorProfile.find_by(user_id: order.buyer_user_id)
    "Order ##{order.order_id.to_s.first(8)}"
  end

  def seller_label(order)
    order.commerce_merchant.display_name
  end
end
