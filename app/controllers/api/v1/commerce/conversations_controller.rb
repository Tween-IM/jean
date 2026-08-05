# frozen_string_literal: true

class Api::V1::Commerce::ConversationsController < Api::V1::Commerce::BaseController
  # POST /api/v1/commerce/products/:product_id/contact
  # Start (or reopen) a classified buyer↔seller conversation for a product.
  # Returns a conversation_id + labels; all messaging goes through the API
  # relay so neither party ever sees the other's Tween/Matrix ID.
  def create
    require_scope("commerce:read")

    product = find_product
    unless product.status == "active"
      return render json: { error: "invalid_product", message: "Product is not available" }, status: :unprocessable_entity
    end

    merchant = product.commerce_merchant
    if merchant.blank? || merchant.owner_user_id.blank?
      return render json: { error: "seller_unavailable", message: "This seller cannot be contacted right now" }, status: :unprocessable_entity
    end

    if merchant.owner_user_id == @current_user.matrix_user_id
      return render json: { error: "self_contact", message: "You can't message your own listing" }, status: :unprocessable_entity
    end

    conversation = ::CommerceConversation.find_by(
      buyer_user_id: @current_user.matrix_user_id,
      product_id: product.product_id
    )
    created = conversation.nil?
    conversation ||= ::CommerceConversation.create!(
      buyer_user_id: @current_user.matrix_user_id,
      product_id: product.product_id
    )

    begin
      CommerceRelayService.create_inquiry_room(conversation)
    rescue CommerceRelayService::Error
      return render json: { error: "relay_unavailable", message: "Could not start a chat with this seller" }, status: :service_unavailable
    end

    render json: {
      conversation: conversation_json(conversation, role: "buyer"),
      created: created
    }, status: :created
  end

  # GET /api/v1/commerce/conversations
  # All conversations the current user participates in, either as buyer or as
  # the merchant owner (seller).
  def index
    require_scope("commerce:read")

    seller_products = ::CommerceProduct
      .where(commerce_merchant: ::CommerceMerchant.where(owner_user_id: @current_user.matrix_user_id))
      .pluck(:product_id)

    conversations = ::CommerceConversation
      .where("buyer_user_id = ? OR product_id IN (?)",
             @current_user.matrix_user_id, seller_products)
      .order(last_message_at: :desc, created_at: :desc)

    render json: {
      conversations: conversations.map { |c| conversation_json(c, role: role_for(c)) }
    }
  end

  # GET /api/v1/commerce/conversations/:id
  def show
    require_scope("commerce:read")

    conversation = find_conversation
    return if ensure_participant(conversation)

    render json: { conversation: conversation_json(conversation, role: role_for(conversation)) }
  end

  # GET /api/v1/commerce/conversations/:id/messages — read history.
  # POST /api/v1/commerce/conversations/:id/messages — send a message.
  def messages
    require_scope("commerce:read")

    conversation = find_conversation
    return if ensure_participant(conversation)

    if request.get?
      return render json: { messages: [] } if conversation.matrix_room_id.blank?

      history = CommerceRelayService.inquiry_room_messages(conversation, limit: (params[:limit] || 50).to_i.clamp(1, 100))
      return render json: { messages: history }
    end

    send_relay_message(conversation)
  rescue CommerceRelayService::Error => e
    Rails.logger.error "[CommerceConversation] Failed to read messages #{conversation.conversation_id}: #{e.message}"
    render json: { error: "relay_unavailable", message: "Could not load messages" }, status: :service_unavailable
  end

  private

  def send_relay_message(conversation)
    body = params[:body].to_s.strip
    return render json: { error: "invalid_message", message: "Message cannot be empty" }, status: :unprocessable_entity if body.blank?

    if conversation.matrix_room_id.blank?
      begin
        CommerceRelayService.create_inquiry_room(conversation)
      rescue CommerceRelayService::Error
        return render json: { error: "relay_unavailable", message: "Could not start a chat with this seller" }, status: :service_unavailable
      end
    end

    role = role_for(conversation)
    CommerceRelayService.relay_inquiry_message(conversation, @current_user.matrix_user_id, body)

    render json: {
      message: {
        id: "local-#{SecureRandom.hex(6)}",
        role: role,
        label: role == "buyer" ? conversation.buyer_label : conversation.seller_label,
        body: body,
        sent_at: (Time.current.to_f * 1000).to_i
      }
    }, status: :created
  end

  def find_conversation
    ::CommerceConversation.find_by!(conversation_id: params[:id] || params[:conversation_id])
  end

  def ensure_participant(conversation)
    return false if role_for(conversation).present?

    render json: { error: "forbidden", message: "Not a participant in this conversation" }, status: :forbidden
    true
  end

  def role_for(conversation)
    return "buyer" if conversation.buyer_user_id == @current_user.matrix_user_id
    return "seller" if conversation.merchant&.owner_user_id == @current_user.matrix_user_id

    nil
  end

  def conversation_json(conversation, role:)
    product = conversation.product
    {
      conversation_id: conversation.conversation_id,
      status: conversation.status,
      role: role,
      buyer_label: conversation.buyer_label,
      seller_label: conversation.seller_label,
      last_message_at: conversation.last_message_at,
      created_at: conversation.created_at,
      product: product ? product_json(product, detail: :public) : nil
    }
  end
end
