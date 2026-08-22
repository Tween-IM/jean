# frozen_string_literal: true

require "digest"

# CommerceRelayService
#
# Creates bot-relayed Matrix rooms for classified (marketplace) buyer↔seller
# conversations. The same conversation system also serves online-store chat
# (buyers message the store from the product page or their order) — there is
# no separate order-chat path. Neither party sees the other's Matrix ID —
# display uses inquiry context labels.
#
# BOT: Reuses the existing TMCP AS token — no new sidecar. Verified against
# the homeserver: MATRIX_AS_TOKEN authenticates as @_tmcp:tween.im and can
# create relay rooms, send, and read history. Resolution order:
# MATRIX_RELAY_TOKEN (explicit override) → MATRIX_AS_TOKEN → MATRIX_HS_TOKEN.
# Event namespacing is carried by the `m.tween.relay` state (relay_type:
# commerce_inquiry).
#
class CommerceRelayService
  # Outgoing homeserver token + which env var it came from (for diagnostics).
  # MATRIX_ACCESS_TOKEN is intentionally excluded — it is a non-production
  # placeholder in some deployments and would shadow the working AS token.
  TOKEN_SOURCE, AS_TOKEN = [
    "MATRIX_RELAY_TOKEN",
    "MATRIX_AS_TOKEN",
    "MATRIX_HS_TOKEN"
  ].filter_map { |key|
    value = ENV[key].presence
    value && [ key, value ]
  }.first || [ nil, "" ]

  class Error < StandardError; end

  # ==========================================================================
  # Classified / store buyer↔seller conversations
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
    conversation.update!(last_message_at: Time.current)

    room_id
  rescue => e
    Rails.logger.error "[CommerceRelay] Failed to create inquiry room for conversation #{conversation.conversation_id}: #{e.message}"
    raise Error, "Failed to create conversation room"
  end

  # Relay a buyer/seller message into the conversation room. Only the bot is
  # a member; the label + role let clients render the other party safely.
  # [media] is an optional hash describing an attachment:
  #   type: image|video|audio|file, url:, mime:, size:, name:, thumbnail_url:
  def self.relay_inquiry_message(conversation, sender_user_id, message_body, media: nil)
    room_id = conversation.matrix_room_id
    return unless room_id.present?

    is_buyer = sender_user_id == conversation.buyer_user_id
    label = is_buyer ? conversation.buyer_label : conversation.seller_label

    content = if media.present?
                media_content(media, caption: message_body)
    else
                {
                  msgtype: "m.text",
                  body: message_body
                }
    end

    content.merge!(
      "m.tween.relay_sender" => label,
      "m.tween.relay_role" => is_buyer ? "buyer" : "seller",
      "m.tween.relay_type" => "commerce_inquiry"
    )

    send_matrix_message(room_id, content)
    conversation.update!(last_message_at: Time.current)

    # Real push to the recipient via their private notification room.
    recipient = is_buyer ? conversation.seller_user_id : conversation.buyer_user_id
    if recipient.present?
      MatrixEventService.publish_commerce_inquiry(
        recipient_user_id: recipient,
        conversation_id: conversation.conversation_id,
        label: label,
        body: message_body
      )
    end
  end

  # Build Matrix media message content (m.image / m.video / m.audio / m.file)
  # from a relay attachment. `url` is the public storage URL.
  def self.media_content(media, caption: nil)
    type = media[:type].to_s
    url = media[:url].to_s
    mime = media[:mime].to_s
    size = media[:size].to_i
    name = media[:name].to_s
    thumbnail_url = media[:thumbnail_url].to_s

    info = { mimetype: mime, size: size }
    info[:thumbnail_url] = thumbnail_url if thumbnail_url.present?

    case type
    when "image"
      {
        msgtype: "m.image",
        body: caption.presence || name.presence || "Photo",
        url: url,
        info: info
      }
    when "video"
      {
        msgtype: "m.video",
        body: caption.presence || name.presence || "Video",
        url: url,
        info: info
      }
    when "audio"
      {
        msgtype: "m.audio",
        body: name.presence || "Voice note",
        url: url,
        info: info
      }
    else
      {
        msgtype: "m.file",
        body: name.presence || "File",
        url: url,
        info: info
      }
    end
  end

  # Read conversation history as the bot. Returns a friendly, ID-free list.
  # Includes both ordinary messages and payment events (m.tween.wallet.p2p,
  # m.tween.money) so the commerce chat can render the same PaymentCard the
  # normal chat uses.
  def self.inquiry_room_messages(conversation, limit: 50)
    room_id = conversation.matrix_room_id
    return [] if room_id.blank?

    response = make_matrix_request(
      :get,
      "/_matrix/client/v3/rooms/#{CGI.escape(room_id)}/messages?dir=b&limit=#{limit.to_i}"
    )

    chunk = response&.dig("chunk") || []
    chunk
      .select { |ev| message_or_payment_event?(ev["type"]) }
      .map do |ev|
        content = ev["content"] || {}
        msgtype = content["msgtype"].to_s
        next if msgtype == "m.notice"

        info = content["info"] || {}
        if offer_event?(ev["type"])
          offer_message_json(ev, content)
        elsif payment_card_event?(ev, content)
          payment_message_json(ev, content)
        else
          {
            id: ev["event_id"],
            role: content["m.tween.relay_role"] || "system",
            label: content["m.tween.relay_sender"] || "Tween",
            body: content["body"].presence || payment_status_body(content),
            sent_at: ev["origin_server_ts"],
            msgtype: content["msgtype"].to_s.delete_prefix("m."),
            media_url: content["url"],
            media_mime: info["mimetype"],
            media_size: info["size"],
            media_name: msgtype == "m.file" ? content["body"] : nil,
            thumbnail_url: info["thumbnail_url"]
          }.compact
        end
      end
      .compact
      .reverse
  end

  # Post a payment event (m.tween.wallet.p2p) into the conversation relay
  # room so both sides see the PaymentCard in the commerce chat.
  def self.relay_payment_event(conversation, payload)
    room_id = conversation.matrix_room_id
    return unless room_id.present?

    content = {
      msgtype: "m.tween.money",
      body: "Paid #{payload[:amount]} #{payload[:currency] || "NGN"}",
      transfer_id: payload[:transfer_id],
      amount: payload[:amount],
      currency: payload[:currency],
      note: payload[:note],
      sender: {
        user_id: payload[:sender_user_id],
        display_name: payload[:sender_label]
      },
      recipient: {
        user_id: payload[:recipient_user_id],
        display_name: payload[:recipient_label]
      },
      status: payload[:status] || "completed",
      "m.tween.relay_role" => "system",
      "m.tween.relay_sender" => "Tween",
      "m.tween.relay_type" => "commerce_payment"
    }.compact

    txn_id = "tween_commerce_pay_#{SecureRandom.hex(16)}"
    make_matrix_request(
      :put,
      "/_matrix/client/v3/rooms/#{CGI.escape(room_id)}/send/m.tween.wallet.p2p/#{txn_id}",
      content
    )
    conversation.update!(last_message_at: Time.current)
  rescue => e
    Rails.logger.error "[CommerceRelay] Failed to relay payment event for conversation #{conversation.conversation_id}: #{e.message}"
    raise Error, "Payment relay failed: #{e.message}"
  end

  # Post a payment status update (m.tween.wallet.p2p.status) into the
  # conversation relay room so both sides' commerce PaymentCard reflects the
  # accept/decline without depending on the DM room.
  def self.relay_payment_status(conversation, transfer_id, status)
    room_id = conversation.matrix_room_id
    return unless room_id.present?

    relay_payment_status_to_room(room_id, transfer_id, status)
  end

  def self.relay_payment_status_to_room(room_id, transfer_id, status)

    content = {
      msgtype: "m.tween.money",
      transfer_id: transfer_id,
      status: status,
      timestamp: Time.current.iso8601,
      "m.tween.relay_role" => "system",
      "m.tween.relay_sender" => "Tween",
      "m.tween.relay_type" => "commerce_payment_status"
    }

    txn_id = "tween_pay_status_#{Digest::SHA256.hexdigest("#{transfer_id}:#{status}")[0, 32]}"
    response = make_matrix_request(
      :put,
      "/_matrix/client/v3/rooms/#{CGI.escape(room_id)}/send/m.tween.wallet.p2p.status/#{txn_id}",
      content
    )
    response["event_id"]
  rescue => e
    Rails.logger.error "[CommerceRelay] Failed to relay payment status to room #{room_id}: #{e.message}"
    raise Error, "Payment status relay failed: #{e.message}"
  end

  def self.relay_payment_event_to_room(room_id, payment)
    transfer_id = payment.fetch(:transfer_id)
    content = {
      msgtype: "m.tween.money",
      body: payment[:body].presence || "Payment request",
      transfer_id: transfer_id,
      amount: payment[:amount],
      currency: payment[:currency],
      status: payment[:status],
      note: payment[:note],
      sender: payment[:sender],
      recipient: payment[:recipient],
      recipient_acceptance_required: payment[:recipient_acceptance_required],
      timestamp: Time.current.iso8601
    }.compact

    txn_id = "tween_pay_#{Digest::SHA256.hexdigest(transfer_id)[0, 32]}"
    response = make_matrix_request(
      :put,
      "/_matrix/client/v3/rooms/#{CGI.escape(room_id)}/send/m.room.message/#{txn_id}",
      content
    )
    response["event_id"]
  rescue => e
    Rails.logger.error "[CommerceRelay] Failed to relay payment event to room #{room_id}: #{e.message}"
    raise Error, "Payment event relay failed: #{e.message}"
  end

  def self.message_or_payment_event?(event_type)
    return true if event_type == "m.room.message"
    offer_event?(event_type) || payment_event?(event_type, nil)
  end

  def self.offer_event?(event_type)
    event_type.to_s.start_with?("m.tween.commerce.offer")
  end

  def self.payment_event?(event_type, msgtype)
    event_type.to_s.start_with?("m.tween.") ||
      msgtype.to_s.start_with?("m.tween.")
  end

  # A full in-chat PaymentCard needs a positive amount. Status-only updates
  # (m.tween.money without an amount, and m.tween.commerce.* events) must not
  # render as "₦0" money cards.
  def self.payment_card_event?(event, content)
    return false unless payment_event?(event["type"], content["msgtype"])
    return false if offer_event?(event["type"])

    amount = content["amount"]
    amount.present? && amount.to_f.positive?
  end

  # Friendly one-liner when a payment/status event has no body and no amount,
  # so it renders as a short system note instead of an empty bubble.
  def self.payment_status_body(content)
    status = content["status"].to_s
    return "Payment #{status}" if status.present?

    nil
  end

  def self.offer_message_json(event, content)
    {
      id: event["event_id"],
      role: content["m.tween.relay_role"] || "system",
      label: content["m.tween.relay_sender"] || "Tween",
      body: content["body"],
      sent_at: event["origin_server_ts"],
      msgtype: "m.tween.commerce.offer",
      is_offer: true,
      offer_id: content["offer_id"],
      offer_type: content["offer_type"],
      offer_version: content["version"],
      offer_status: content["status"],
      currency: content["currency"],
      total_cents: content["total_cents"],
      seller_proceeds_cents: content["seller_proceeds_cents"],
      offer_expires_at: content["expires_at"]
    }.compact
  end

  def self.payment_message_json(event, content)
    sender = content["sender"] || {}
    recipient = content["recipient"] || {}
    sender_id = sender.is_a?(Hash) ? sender["user_id"] : sender
    recipient_id = recipient.is_a?(Hash) ? recipient["user_id"] : recipient
    sender_name = sender.is_a?(Hash) ? sender["display_name"] : nil
    recipient_name = recipient.is_a?(Hash) ? recipient["display_name"] : nil

    {
      id: event["event_id"],
      role: content["m.tween.relay_role"] || "system",
      label: content["m.tween.relay_sender"] || "Tween",
      body: content["body"],
      sent_at: event["origin_server_ts"],
      msgtype: "m.tween.money",
      is_payment: true,
      amount: content["amount"],
      currency: content["currency"],
      transfer_id: content["transfer_id"],
      status: content["status"],
      sender_id: sender_id,
      sender_name: sender_name,
      recipient_id: recipient_id,
      recipient_name: recipient_name,
      note: content["note"]
    }.compact
  end

  # ==========================================================================
  # Direct-chat promotion
  # ==========================================================================
  #
  # When a party opts in, create a REAL DM room between buyer and seller so
  # both can continue with the full chat experience (composer, push, ...).
  # The relay conversation stays as context. Neither party is revealed to the
  # other before both sides consent (the room is created, but the buyer only
  # joins after accepting).
  #
  # WhatsApp-style dedup: one shared 1:1 room per (buyer, seller) pair. No
  # matter how many product conversations they share, they reuse the same
  # room. The room carries m.tween.commerce_dm with both labels so the client
  # can title it per viewer (buyer sees the storefront name, seller sees the
  # customer name).
  def self.create_dm_room(conversation)
    return conversation.dm_room_id if conversation.dm_room_id.present?

    buyer = conversation.buyer_user_id
    seller = conversation.seller_user_id
    return if buyer.blank? || seller.blank?

    existing = ::CommerceDmRoom.for_pair(buyer, seller)
    if existing
      conversation.update!(dm_room_id: existing.matrix_room_id)
      return existing.matrix_room_id
    end

    room_id = create_matrix_room(
      # No room name: the client titles a m.tween.commerce_dm room per viewer
      # using the buyer_label/seller_label state below (buyer sees the
      # storefront name, seller sees the customer name). Leaving it unnamed
      # avoids leaking one party's name to the other.
      name: nil,
      invite: [ buyer, seller ].compact,
      is_direct: true,
      preset: "trusted_private_chat",
      initial_state: [ {
        type: "m.tween.commerce_dm",
        content: {
          conversation_id: conversation.conversation_id,
          buyer_user_id: buyer,
          seller_user_id: seller,
          buyer_label: conversation.buyer_label,
          seller_label: conversation.seller_label
        }
      } ]
    )

    ::CommerceDmRoom.create!(
      buyer_user_id: buyer,
      seller_user_id: seller,
      matrix_room_id: room_id
    )
    conversation.update!(dm_room_id: room_id)
    room_id
  rescue ActiveRecord::RecordInvalid => e
    # Race between two concurrent offers for the same pair: re-read and reuse.
    Rails.logger.info "[CommerceRelay] DM dedup race for (#{conversation.buyer_user_id}, #{conversation.seller_user_id}): #{e.message}"
    existing = ::CommerceDmRoom.for_pair(conversation.buyer_user_id, conversation.seller_user_id)
    if existing
      conversation.update!(dm_room_id: existing.matrix_room_id)
      return existing.matrix_room_id
    end
    raise Error, "Failed to create direct chat room"
  rescue => e
    Rails.logger.error "[CommerceRelay] Failed to create DM room for conversation #{conversation.conversation_id}: #{e.message}"
    raise Error, "Failed to create direct chat room"
  end

  # Post a system notice (role "system") into the relay room.
  def self.send_system_message(room_id, text)
    return unless room_id.present?

    send_matrix_message(room_id, {
      msgtype: "m.text",
      body: text,
      "m.tween.relay_sender" => "Tween",
      "m.tween.relay_role" => "system",
      "m.tween.relay_type" => "commerce_inquiry"
    })
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
