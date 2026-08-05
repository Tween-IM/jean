# frozen_string_literal: true

# CommerceRelayService
#
# Creates bot-relayed Matrix rooms for buyer-seller messaging (order chat and
# classified marketplace conversations). Neither party sees the other's
# Matrix ID — display uses order/inquiry context labels.
#
# BOT: Reuses an existing TMCP bot token — no new sidecar. Resolution order:
# MATRIX_ACCESS_TOKEN (documented "access token for event publishing") →
# MATRIX_HS_TOKEN (AS hs_token) → MATRIX_AS_TOKEN (legacy name). The token
# is sent as a Bearer, acting as whatever bot user owns it. Event
# namespacing is carried by the `m.tween.relay` state (relay_type:
# commerce_order / commerce_inquiry).
#
class CommerceRelayService
  # Outgoing homeserver token + which env var it came from (for diagnostics).
  TOKEN_SOURCE, AS_TOKEN = [
    "MATRIX_RELAY_TOKEN",
    "MATRIX_ACCESS_TOKEN",
    "MATRIX_HS_TOKEN",
    "MATRIX_AS_TOKEN"
  ].filter_map { |key|
    value = ENV[key].presence
    value && [ key, value ]
  }.first || [ nil, "" ]

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
  # The @_tmcp AS bot owns the room. Neither party is a member, so nobody
  # ever sees the other's Tween/Matrix ID — only the friendly labels below.

  def self.create_inquiry_room(conversation)
    return conversation.matrix_room_id if conversation.matrix_room_id.present?

    product = conversation.product
    room_id = create_matrix_room(
      name: nil,
      invite: [],
      is_direct: false,
      preset: "trusted_private_chat",
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

  # Call the homeserver as the TMCP AS user (@_tmcp). The AS hs_token with no
  # user_id acts as the registered sender user — the same path used by
  # PaymentBotService / MatrixService.
  def self.make_matrix_request(method, path, body = nil)
    url = "#{matrix_base_url}#{path}"
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
      body = response.body.to_s[0..300]
      Rails.logger.error(
        "[CommerceRelay] Matrix #{method.upcase} #{url} failed: " \
        "#{response.status} #{body} (token_source=#{TOKEN_SOURCE})"
      )
      raise Error, "Matrix API error: #{response.status} #{body}"
    end

    JSON.parse(response.body) unless response.body.blank?
  end

  def self.matrix_base_url
    ENV["MATRIX_API_URL"].presence ||
      ENV["MATRIX_HOMESERVER_URL"].presence ||
      "https://core.tween.im"
  end
end
