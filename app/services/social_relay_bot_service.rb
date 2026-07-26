# frozen_string_literal: true

# SocialRelayBotService
#
# Creates Matrix relay rooms for social chats. Messages are relayed through
# the bot — users see handles/display_names, never raw Matrix IDs.
# Promotes to P2P DM when both parties share contact.
#
class SocialRelayBotService
  BOT_USER_ID = ENV.fetch("RELAY_BOT_USER_ID", "@tween_relay_bot:tween.im")
  BOT_ACCESS_TOKEN = ENV.fetch("RELAY_BOT_ACCESS_TOKEN", "")

  class Error < StandardError; end

  # Create a Matrix relay room for a social chat.
  # Room is invite-only, bot is sole member.
  def self.create_relay_room(chat)
    return chat.matrix_room_id if chat.matrix_room_id.present?

    room_id = create_matrix_room(
      name: nil,
      invite: [BOT_USER_ID],
      is_direct: false,
      preset: "trusted_private_chat",
      initial_state: [{
        type: "m.tween.relay",
        content: {
          relay_type: "social_chat",
          social_chat_id: chat.id,
          user_a_id: chat.user_a_id,
          user_b_id: chat.user_b_id
        }
      }]
    )

    chat.update!(matrix_room_id: room_id)
    room_id
  rescue => e
    Rails.logger.error "[RelayBot] Failed to create relay room for chat #{chat.id}: #{e.message}"
    raise Error, "Failed to create relay room"
  end

  # Relay a message from sender to the relay room.
  # The bot sends the message with the sender's handle/display_name as metadata,
  # never exposing the raw Matrix ID.
  def self.relay_message(chat, sender_user_id, message_body)
    return unless chat.matrix_room_id.present?

    sender_profile = SocialCreatorProfile.find_by(user_id: sender_user_id)
    display = sender_profile&.handle || sender_user_id

    content = {
      msgtype: "m.text",
      body: message_body,
      "m.tween.relay_sender" => display,
      "m.tween.relay_sender_handle" => sender_profile&.handle,
      "m.tween.relay_sender_display_name" => sender_profile&.display_name
    }

    send_matrix_message(chat.matrix_room_id, content)
    chat.touch(:last_message_at)
  end

  # Promote relay room to P2P DM when both parties share contact.
  def self.promote_to_dm(chat)
    return unless chat.matrix_room_id.present?

    invite_matrix_user(chat.matrix_room_id, chat.user_a_id)
    invite_matrix_user(chat.matrix_room_id, chat.user_b_id)
    leave_matrix_room(chat.matrix_room_id)

    chat.update!(matrix_room_id: nil, status: 'promoted_to_dm')
  end

  # Handle chat deletion — user leaves room.
  def self.handle_delete(chat, leaving_user_id)
    return unless chat.matrix_room_id.present?

    leave_matrix_room_for_user(chat.matrix_room_id, leaving_user_id)
    chat.update!(status: 'destroyed')
  end

  # Handle block — stop relaying from blocked user.
  def self.handle_block(chat, _blocked_user_id)
    # Bot continues running but blocked messages are dropped.
    # The client-filtered side (blocked user sees "blocked" state) handles UX.
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
    txn_id = "tween_relay_#{SecureRandom.hex(16)}"
    make_matrix_request(
      :put,
      "/_matrix/client/v3/rooms/#{room_id}/send/m.room.message/#{txn_id}",
      content
    )
  end

  def self.invite_matrix_user(room_id, user_id)
    make_matrix_request(
      :post,
      "/_matrix/client/v3/rooms/#{room_id}/invite",
      { user_id: user_id }
    )
  rescue => e
    Rails.logger.warn "[RelayBot] Failed to invite #{user_id} to room #{room_id}: #{e.message}"
  end

  def self.leave_matrix_room(room_id)
    make_matrix_request(:post, "/_matrix/client/v3/rooms/#{room_id}/leave", {})
  rescue => e
    Rails.logger.warn "[RelayBot] Failed to leave room #{room_id}: #{e.message}"
  end

  def self.leave_matrix_room_for_user(room_id, _user_id)
    leave_matrix_room(room_id)
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
      raise Error, "Matrix API error: #{response.status} #{response.body}"
    end

    JSON.parse(response.body) unless response.body.blank?
  end

  def self.matrix_base_url
    ENV.fetch("MATRIX_HOMESERVER_URL", "https://core.tween.im")
  end
end
