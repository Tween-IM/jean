# frozen_string_literal: true

# CommerceRelayService
#
# Creates bot-relayed Matrix rooms for buyer-seller messaging (order chat and
# classified marketplace conversations). Neither party sees the other's
# Matrix ID — display uses order/inquiry context labels.
#
# BOT: Reuses the TMCP Application Service bot configuration (registered in
# matrix-homeserver-config.yaml with sender_localpart "_tmcp"). Acting as the
# virtual user @_tmcp_commerce via AS identity assertion (hs_token +
# ?user_id=), so NO separate sidecar bot is required. The @_tmcp.* users
# namespace is exclusive to the AS, which lets us expand to commerce-specific
# identities like @_tmcp_commerce freely.
#
class CommerceRelayService
  # Virtual commerce bot within the AS's exclusive @_tmcp.* namespace.
  BOT_USER_ID = "@_tmcp_commerce:#{ENV.fetch('MATRIX_DOMAIN', 'tween.im')}".freeze

  # hs_token authenticates TMCP Server to the homeserver as the AS
  # (matrix-homeserver-config.yaml). Fall back to MATRIX_AS_TOKEN where that
  # legacy name is in use.
  AS_TOKEN = ENV["MATRIX_AS_TOKEN"].presence || ENV.fetch("MATRIX_HS_TOKEN", "")

  class Error < StandardError; end

  def self.create_order_room(order)
    buyer = order.buyer_user_id
    seller = order.commerce_merchant.owner_user_id

    room_id = create_matrix_room(
      name: nil,
      invite: [],
      is_direct: false,
      preset: "trusted_private_chat",
      initial_state: [ {
        type: "m.tween.relay",
        content: {
          relay_type: "commerce_order",
          order_id: order.order_id,
          buyer_user_id: buyer,
          seller_user_id: seller,
          buyer_label: "Order ##{order.order_id.to_s.first(8)}",
          seller_label: order.commerce_merchant.display_name
        }
      } ]
    )

    room_id
  rescue => e
    Rails.logger.error "[CommerceRelay] Failed to create room for order #{order.order_id}: #{e.message}"
    raise Error, "Failed to create commerce relay room"
  end

  def self.relay_message(order, sender_user_id, message_body)
    room_id = order.metadata&.dig("commerce_room_id")
    return unless room_id.present?

    is_buyer = sender_user_id == order.buyer_user_id
    label = is_buyer ? "Order ##{order.order_id.to_s.first(8)}" : order.commerce_merchant.display_name

    content = {
      msgtype: "m.text",
      body: message_body,
      "m.tween.relay_sender" => label,
      "m.tween.relay_type" => "commerce_order"
    }

    send_matrix_message(room_id, content)
  end

  # ==========================================================================
  # Classified (marketplace) buyer↔seller conversations
  # ==========================================================================
  #
  # The @_tmcp_commerce bot owns the room. Neither party is a member, so
  # nobody ever sees the other's Tween/Matrix ID — only the friendly labels
  # below.

  def self.create_inquiry_room(conversation)
    return conversation.matrix_room_id if conversation.matrix_room_id.present?

    product = conversation.product
    room_id = create_matrix_room(
      name: nil,
      invite: [],
      is_direct: false,
      preset: "trusted_private_chat",
      room_alias_name: "tmcp_inquiry_#{conversation.conversation_id}",
      initial_state: [ {
        type: "m.tween.relay",
        content: {
          relay_type: "commerce_inquiry",
          conversation_id: conversation.conversation_id,
          product_id: conversation.product_id,
          product_title: product&.title,
          buyer_user_id: conversation.buyer_user_id,
          seller_user_id: conversation.seller_user_id,
          buyer_label: conversation.buyer_label,
          seller_label: conversation.seller_label
        }
      } ]
    )

    conversation.update!(matrix_room_id: room_id)

    # Seed a system context message so both sides see what the chat is about.
    send_matrix_message(room_id, {
      msgtype: "m.text",
      body: "New inquiry about: #{product&.title}",
      "m.tween.relay_sender" => "Tween",
      "m.tween.relay_role" => "system",
      "m.tween.relay_type" => "commerce_inquiry"
    })

    room_id
  rescue => e
    Rails.logger.error "[CommerceRelay] Failed to create inquiry room for conversation #{conversation.conversation_id}: #{e.message}"
    raise Error, "Failed to create conversation room"
  end

  # Relay a buyer/seller message into the conversation room. Only the bot is
  # a member; the label + role let clients render the other party safely.
  def self.relay_inquiry_message(conversation, sender_user_id, message_body)
    room_id = conversation.matrix_room_id
    return unless room_id.present?

    is_buyer = sender_user_id == conversation.buyer_user_id
    label = is_buyer ? conversation.buyer_label : conversation.seller_label

    content = {
      msgtype: "m.text",
      body: message_body,
      "m.tween.relay_sender" => label,
      "m.tween.relay_role" => is_buyer ? "buyer" : "seller",
      "m.tween.relay_type" => "commerce_inquiry"
    }

    send_matrix_message(room_id, content)
    conversation.update!(last_message_at: Time.current)
  end

  # Read conversation history as the bot. Returns a friendly, ID-free list.
  def self.inquiry_room_messages(conversation, limit: 50)
    room_id = conversation.matrix_room_id
    return [] if room_id.blank?

    response = make_matrix_request(
      :get,
      "/_matrix/client/v3/rooms/#{CGI.escape(room_id)}/messages?dir=b&limit=#{limit.to_i}"
    )

    chunk = response&.dig("chunk") || []
    chunk
      .select { |ev| ev["type"] == "m.room.message" && ev.dig("content", "msgtype") == "m.text" }
      .map do |ev|
        content = ev["content"] || {}
        {
          id: ev["event_id"],
          role: content["m.tween.relay_role"] || "system",
          label: content["m.tween.relay_sender"] || "Tween",
          body: content["body"],
          sent_at: ev["origin_server_ts"]
        }
      end
      .reverse
  end

  private

  def self.create_matrix_room(params)
    body = {
      creation_content: { "m.federate": false },
      preset: params[:preset] || "trusted_private_chat",
      invite: params[:invite] || [],
      is_direct: params[:is_direct] || false,
      initial_state: params[:initial_state] || [],
      room_alias_name: params[:room_alias_name],
      name: params[:name]
    }.compact

    response = make_matrix_request(:post, "/_matrix/client/v3/createRoom", body)
    response["room_id"]
  end

  def self.send_matrix_message(room_id, content)
    txn_id = "tween_commerce_#{SecureRandom.hex(16)}"
    make_matrix_request(
      :put,
      "/_matrix/client/v3/rooms/#{CGI.escape(room_id)}/send/m.room.message/#{txn_id}",
      content
    )
  end

  # Call the homeserver as the AS bot (@_tmcp_commerce). The user_id query
  # param is the Matrix Application Service identity assertion — events and
  # room creation are attributed to the virtual bot, not to any human user.
  def self.make_matrix_request(method, path, body = nil, user_id: BOT_USER_ID)
    url = matrix_request_url(path, user_id: user_id)
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{AS_TOKEN}"
    }

    response = case method
    when :post then Faraday.post(url, body&.to_json, headers)
    when :put  then Faraday.put(url, body&.to_json, headers)
    when :get  then Faraday.get(url, nil, headers)
    else raise "Unsupported method: #{method}"
    end

    unless response.success?
      raise Error, "Matrix API error: #{response.status}"
    end

    JSON.parse(response.body) unless response.body.blank?
  end

  def self.matrix_request_url(path, user_id:)
    uri = URI("#{matrix_base_url}#{path}")
    query = URI.decode_www_form(uri.query.to_s)
    query << [ "user_id", user_id ]
    uri.query = URI.encode_www_form(query)
    uri.to_s
  end

  def self.matrix_base_url
    ENV["MATRIX_API_URL"].presence ||
      ENV["MATRIX_HOMESERVER_URL"].presence ||
      "https://core.tween.im"
  end
end
