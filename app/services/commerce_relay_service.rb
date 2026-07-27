# frozen_string_literal: true

# CommerceRelayService
#
# Creates bot-relayed Matrix rooms for order-based buyer-seller messaging.
# Neither party sees the other's Matrix ID — display uses order context labels.
# Bot stays in the room permanently (no promotion to DM for commerce).
#
class CommerceRelayService
  # Reuse the same bot credentials from SocialRelayBotService
  BOT_USER_ID = ENV.fetch("RELAY_BOT_USER_ID", "@tween_relay_bot:tween.im")
  BOT_ACCESS_TOKEN = ENV.fetch("RELAY_BOT_ACCESS_TOKEN", "")

  class Error < StandardError; end

  def self.create_order_room(order)
    buyer = order.buyer_user_id
    seller = order.commerce_merchant.owner_user_id

    room_id = create_matrix_room(
      name: nil,
      invite: [BOT_USER_ID],
      is_direct: false,
      preset: "trusted_private_chat",
      initial_state: [{
        type: "m.tween.relay",
        content: {
          relay_type: "commerce_order",
          order_id: order.order_id,
          buyer_user_id: buyer,
          seller_user_id: seller,
          buyer_label: "Order ##{order.order_id.to_s.first(8)}",
          seller_label: order.commerce_merchant.display_name
        }
      }]
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

  def self.handle_delete(order, _leaving_user_id)
    # Commerce rooms are persistent — just stop relaying.
    # Room remains accessible from order detail.
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
      "/_matrix/client/v3/rooms/#{room_id}/send/m.room.message/#{txn_id}",
      content
    )
  end

  def self.make_matrix_request(method, path, body = nil)
    url = "#{matrix_base_url}#{path}"
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{BOT_ACCESS_TOKEN}"
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

  def self.matrix_base_url
    ENV.fetch("MATRIX_HOMESERVER_URL", "https://core.tween.im")
  end
end
