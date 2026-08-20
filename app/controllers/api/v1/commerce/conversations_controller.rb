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

  # PATCH /api/v1/commerce/conversations/:id — close or reopen.
  def update
    require_scope("commerce:read")

    conversation = find_conversation
    return if ensure_participant(conversation)

    status = params[:status].to_s
    unless status.in?(%w[open closed])
      return render json: { error: "invalid_status", message: "Status must be 'open' or 'closed'" }, status: :unprocessable_entity
    end

    conversation.update!(status: status)
    render json: { conversation: conversation_json(conversation, role: role_for(conversation)) }
  end

  # POST /api/v1/commerce/conversations/:id/read — mark the caller's copy read.
  def read
    require_scope("commerce:read")

    conversation = find_conversation
    return if ensure_participant(conversation)

    conversation.mark_read!(role_for(conversation))
    render json: { conversation: conversation_json(conversation, role: role_for(conversation)) }
  end

  # POST /api/v1/commerce/conversations/:id/offer_dm
  # A participant offers to continue in a real direct chat. Creates the DM
  # room (both invited) but the counterparty only joins after accepting.
  # Only the party who did NOT offer may accept.
  def offer_dm
    require_scope("commerce:read")

    conversation = find_conversation
    return if ensure_participant(conversation)

    role = role_for(conversation)
    if conversation.status.in?(%w[dm_pending dm_active])
      return render json: { conversation: conversation_json(conversation, role: role) }
    end

    if conversation.dm_offered_by.present? && conversation.dm_offered_by == role
      return render json: { error: "already_offered", message: "You already offered a direct chat" }, status: :unprocessable_entity
    end

    begin
      CommerceRelayService.create_dm_room(conversation)
    rescue CommerceRelayService::Error
      return render json: { error: "relay_unavailable", message: "Could not create a direct chat" }, status: :service_unavailable
    end

    conversation.update!(status: "dm_pending", dm_offered_by: role)
    offering_label = role == "buyer" ? conversation.buyer_label : conversation.seller_label
    CommerceRelayService.send_system_message(
      conversation.matrix_room_id,
      "#{offering_label} wants to continue in a direct chat."
    )

    render json: { conversation: conversation_json(conversation, role: role) }
  end

  # POST /api/v1/commerce/conversations/:id/accept_dm
  # Only the party who did NOT offer may accept (the offerer cannot accept
  # their own request — that would impersonate the counterparty).
  def accept_dm
    require_scope("commerce:read")

    conversation = find_conversation
    return if ensure_participant(conversation)

    if conversation.dm_room_id.blank?
      return render json: { error: "no_dm", message: "No direct chat has been offered" }, status: :unprocessable_entity
    end

    role = role_for(conversation)
    if conversation.status != "dm_pending"
      return render json: { error: "invalid_dm_state", message: "This direct chat is not pending acceptance" }, status: :unprocessable_entity
    end

    if conversation.dm_offered_by == role
      return render json: { error: "self_accept", message: "You offered this direct chat; only the other party can accept" }, status: :forbidden
    end

    conversation.update!(status: "dm_active")
    conversation.mark_read!(role)

    render json: {
      conversation: conversation_json(conversation, role: role),
      dm_room_id: conversation.dm_room_id
    }
  end

  # POST /api/v1/commerce/conversations/:id/decline_dm
  def decline_dm
    require_scope("commerce:read")

    conversation = find_conversation
    return if ensure_participant(conversation)

    conversation.update!(status: "open", dm_offered_by: nil)
    render json: { conversation: conversation_json(conversation, role: role_for(conversation)) }
  end

  # GET /api/v1/commerce/conversations/:id/payment_recipient
  # Resolve the counterparty's Matrix ID for the in-chat payment flow only.
  #
  # Privacy: this ID is intentionally NOT included in any relay/chat payload
  # (the relay hides both parties' IDs). It is returned here, scoped to a
  # participant, solely so the client can drive the shared P2P transfer
  # bottom sheet. The recipient is the person you are already talking to.
  def payment_recipient
    require_scope("commerce:read")

    conversation = find_conversation
    return if ensure_participant(conversation)

    role = role_for(conversation)
    recipient_user_id = role == "buyer" ? conversation.seller_user_id : conversation.buyer_user_id
    recipient_label = role == "buyer" ? conversation.seller_label : conversation.buyer_label

    if recipient_user_id.blank?
      return render json: { error: "no_recipient", message: "This conversation has no payment recipient" }, status: :unprocessable_entity
    end

    render json: {
      recipient_user_id: recipient_user_id,
      recipient_label: recipient_label,
      role: role
    }
  end

  # POST /api/v1/commerce/conversations/:id/payments/relay
  # Mirror a completed in-chat P2P payment into the conversation relay room so
  # both sides see the PaymentCard (the same card the normal chat renders).
  # The payment itself is executed against the wallet service by the client;
  # this only posts the display event. IDs are resolved server-side.
  def payment_relay
    require_scope("commerce:read")

    conversation = find_conversation
    return if ensure_participant(conversation)

    transfer_id = params[:transfer_id].to_s
    amount = params[:amount]
    currency = params[:currency].presence || "NGN"
    status = params[:status].presence || "completed"
    note = params[:note].to_s.presence

    if transfer_id.blank? || amount.nil?
      return render json: { error: "invalid_payment", message: "Transfer id and amount are required" }, status: :unprocessable_entity
    end

    role = role_for(conversation)
    sender_user_id = @current_user.matrix_user_id
    recipient_user_id = role == "buyer" ? conversation.seller_user_id : conversation.buyer_user_id
    sender_label = role == "buyer" ? conversation.buyer_label : conversation.seller_label
    recipient_label = role == "buyer" ? conversation.seller_label : conversation.buyer_label

    CommerceRelayService.relay_payment_event(
      conversation,
      transfer_id: transfer_id,
      amount: amount.to_f,
      currency: currency,
      status: status,
      note: note,
      sender_user_id: sender_user_id,
      sender_label: sender_label,
      recipient_user_id: recipient_user_id,
      recipient_label: recipient_label
    )

    render json: { status: "relayed" }
  rescue CommerceRelayService::Error => e
    Rails.logger.error "[PaymentRelay] #{conversation.conversation_id}: #{e.message}"
    render json: { error: "relay_failed", message: "Could not relay the payment into the chat" }, status: :service_unavailable
  end

  # POST /api/v1/commerce/conversations/:id/payments/relay_status
  # Mirror a P2P payment status change (accepted/rejected) into the
  # conversation relay room so both sides' commerce PaymentCard updates
  # without depending on the DM room.
  def payment_relay_status
    require_scope("commerce:read")

    conversation = find_conversation
    return if ensure_participant(conversation)

    transfer_id = params[:transfer_id].to_s
    status = params[:status].to_s

    unless transfer_id.present? && %w[completed rejected].include?(status)
      return render json: { error: "invalid_status", message: "Transfer id and a completed/rejected status are required" }, status: :unprocessable_entity
    end

    CommerceRelayService.relay_payment_status(conversation, transfer_id, status)

    render json: { status: "relayed" }
  rescue CommerceRelayService::Error => e
    Rails.logger.error "[PaymentRelayStatus] #{conversation.conversation_id}: #{e.message}"
    render json: { error: "relay_failed", message: "Could not relay the payment status into the chat" }, status: :service_unavailable
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
    media = media_params

    if body.blank? && media.blank?
      return render json: { error: "invalid_message", message: "Message cannot be empty" }, status: :unprocessable_entity
    end

    if conversation.matrix_room_id.blank?
      begin
        CommerceRelayService.create_inquiry_room(conversation)
      rescue CommerceRelayService::Error
        return render json: { error: "relay_unavailable", message: "Could not start a chat with this seller" }, status: :service_unavailable
      end
    end

    role = role_for(conversation)
    CommerceRelayService.relay_inquiry_message(
      conversation,
      @current_user.matrix_user_id,
      body,
      media: media
    )

    render json: {
      message: {
        id: "local-#{SecureRandom.hex(6)}",
        role: role,
        label: role == "buyer" ? conversation.buyer_label : conversation.seller_label,
        body: body,
        sent_at: (Time.current.to_f * 1000).to_i,
        msgtype: media ? media[:type] : "text",
        media_url: media&.dig(:url),
        media_mime: media&.dig(:mime),
        media_size: media&.dig(:size),
        media_name: media&.dig(:name),
        thumbnail_url: media&.dig(:thumbnail_url)
      }.compact
    }, status: :created
  end

  def media_params
    type = params[:media_type].to_s
    url = params[:media_url].to_s
    return nil if type.blank? || url.blank?
    return nil unless type.in?(%w[image video audio file])

    {
      type: type,
      url: url,
      mime: params[:media_mime].to_s,
      size: params[:media_size].to_i,
      name: params[:media_name].to_s,
      thumbnail_url: params[:thumbnail_url].to_s
    }
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
      unread: conversation.unread_for?(role),
      buyer_label: conversation.buyer_label,
      seller_label: conversation.seller_label,
      dm_room_id: conversation.dm_room_id,
      dm_offered_by: conversation.dm_offered_by,
      last_message_at: conversation.last_message_at,
      created_at: conversation.created_at,
      product: product ? product_json(product, detail: :public) : nil
    }
  end
end
