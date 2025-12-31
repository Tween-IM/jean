class PaymentBotService
  PAYMENT_BOT_USER_ID = "@_tmcp_payments:tween.example".freeze
  PAYMENT_BOT_DISPLAY_NAME = "Tween Payments".freeze

  class PaymentBotError < StandardError; end

  attr_reader :as_token, :matrix_api_url

  def initialize(config = {})
    @as_token = config[:as_token] || ENV["MATRIX_AS_TOKEN"]
    @matrix_api_url = config[:matrix_api_url] || ENV["MATRIX_API_URL"] || "https://matrix.tween.example"
  end

  def payment_bot_user_id
    PAYMENT_BOT_USER_ID
  end

  def send_payment_completed(room_id:, payment_data:)
    idempotency_key = "payment_event:#{payment_data[:payment_id]}"

    existing_event_id = Rails.cache.read(idempotency_key)
    return existing_event_id if existing_event_id

    event_content = build_payment_completed_content(payment_data)

    event_id = send_event(
      room_id: room_id,
      event_type: "m.tween.payment.completed",
      event_content: event_content
    )

    Rails.cache.write(idempotency_key, event_id, expires_in: 24.hours) if event_id

    event_id
  end

  def send_payment_sent(room_id:, payment_data:)
    idempotency_key = "payment_sent_event:#{payment_data[:payment_id]}"

    existing_event_id = Rails.cache.read(idempotency_key)
    return existing_event_id if existing_event_id

    event_content = build_payment_sent_content(payment_data)

    event_id = send_event(
      room_id: room_id,
      event_type: "m.tween.payment.sent",
      event_content: event_content
    )

    Rails.cache.write(idempotency_key, event_id, expires_in: 24.hours) if event_id

    event_id
  end

  def send_payment_failed(room_id:, payment_data:)
    event_content = build_payment_failed_content(payment_data)

    send_event(
      room_id: room_id,
      event_type: "m.tween.payment.failed",
      event_content: event_content
    )
  end

  def send_payment_refunded(room_id:, payment_data:)
    event_content = build_payment_refunded_content(payment_data)

    send_event(
      room_id: room_id,
      event_type: "m.tween.payment.refunded",
      event_content: event_content
    )
  end

  def send_p2p_transfer(room_id:, transfer_data:)
    idempotency_key = "p2p_transfer_event:#{transfer_data[:transfer_id]}"

    existing_event_id = Rails.cache.read(idempotency_key)
    return existing_event_id if existing_event_id

    event_content = build_p2p_transfer_content(transfer_data)

    event_id = send_event(
      room_id: room_id,
      event_type: "m.tween.p2p.transfer",
      event_content: event_content
    )

    Rails.cache.write(idempotency_key, event_id, expires_in: 24.hours) if event_id

    event_id
  end

  private

  def build_payment_completed_content(payment_data)
    {
      msgtype: "m.tween.payment",
      payment_type: "completed",
      visual: {
        card_type: "payment_receipt",
        icon: "payment_completed",
        background_color: "#4CAF50"
      },
      transaction: {
        txn_id: payment_data[:txn_id],
        amount: payment_data[:amount],
        currency: payment_data[:currency]
      },
      sender: {
        user_id: payment_data[:sender_user_id],
        display_name: payment_data[:sender_display_name],
        avatar_url: payment_data[:sender_avatar_url]
      },
      recipient: {
        user_id: payment_data[:recipient_user_id],
        display_name: payment_data[:recipient_display_name],
        avatar_url: payment_data[:recipient_avatar_url]
      },
      note: payment_data[:note] || "",
      timestamp: payment_data[:timestamp] || Time.current.iso8601,
      actions: [
        {
          type: "view_receipt",
          label: "View Details",
          endpoint: "/wallet/v1/transactions/#{payment_data[:txn_id]}"
        }
      ]
    }
  end

  def build_payment_sent_content(payment_data)
    {
      msgtype: "m.tween.payment",
      payment_type: "sent",
      visual: {
        card_type: "payment_sent",
        icon: "payment_sent",
        background_color: "#2196F3"
      },
      transaction: {
        txn_id: payment_data[:txn_id],
        amount: payment_data[:amount],
        currency: payment_data[:currency]
      },
      sender: {
        user_id: payment_data[:sender_user_id],
        display_name: payment_data[:sender_display_name],
        avatar_url: payment_data[:sender_avatar_url]
      },
      recipient: {
        user_id: payment_data[:recipient_user_id],
        display_name: payment_data[:recipient_display_name],
        avatar_url: payment_data[:recipient_avatar_url]
      },
      note: payment_data[:note] || "",
      timestamp: payment_data[:timestamp] || Time.current.iso8601,
      actions: [
        {
          type: "view_receipt",
          label: "View Details",
          endpoint: "/wallet/v1/transactions/#{payment_data[:txn_id]}"
        }
      ]
    }
  end

  def build_payment_failed_content(payment_data)
    {
      msgtype: "m.tween.payment",
      payment_type: "failed",
      visual: {
        card_type: "payment_failed",
        icon: "payment_failed",
        background_color: "#F44336"
      },
      transaction: {
        txn_id: payment_data[:txn_id],
        amount: payment_data[:amount],
        currency: payment_data[:currency]
      },
      sender: {
        user_id: payment_data[:sender_user_id],
        display_name: payment_data[:sender_display_name]
      },
      recipient: {
        user_id: payment_data[:recipient_user_id],
        display_name: payment_data[:recipient_display_name]
      },
      error: {
        code: payment_data[:error_code] || "UNKNOWN_ERROR",
        message: payment_data[:error_message] || "Payment failed"
      },
      timestamp: payment_data[:timestamp] || Time.current.iso8601
    }
  end

  def build_payment_refunded_content(payment_data)
    {
      msgtype: "m.tween.payment",
      payment_type: "refunded",
      visual: {
        card_type: "payment_refunded",
        icon: "payment_refunded",
        background_color: "#FF9800"
      },
      transaction: {
        txn_id: payment_data[:original_txn_id],
        refund_txn_id: payment_data[:refund_txn_id],
        amount: payment_data[:amount],
        currency: payment_data[:currency]
      },
      sender: {
        user_id: payment_data[:sender_user_id],
        display_name: payment_data[:sender_display_name]
      },
      recipient: {
        user_id: payment_data[:recipient_user_id],
        display_name: payment_data[:recipient_display_name]
      },
      reason: payment_data[:reason] || "",
      timestamp: payment_data[:timestamp] || Time.current.iso8601
    }
  end

  def build_p2p_transfer_content(transfer_data)
    {
      msgtype: "m.tween.money",
      body: "💸 Sent #{transfer_data[:amount]} #{transfer_data[:currency]}",
      transfer_id: transfer_data[:transfer_id],
      amount: transfer_data[:amount],
      currency: transfer_data[:currency],
      note: transfer_data[:note] || "",
      sender: {
        user_id: transfer_data[:sender_user_id],
        display_name: transfer_data[:sender_display_name]
      },
      recipient: {
        user_id: transfer_data[:recipient_user_id],
        display_name: transfer_data[:recipient_display_name]
      },
      status: transfer_data[:status] || "completed",
      timestamp: transfer_data[:timestamp] || Time.current.iso8601
    }
  end

  def send_event(room_id:, event_type:, event_content:)
    return unless @as_token

    uri = URI("#{@matrix_api_url}/_matrix/client/v3/rooms/#{room_id}/send/#{event_type}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{@as_token}"
    request["Content-Type"] = "application/json"
    request.body = event_content.to_json

    response = http.request(request)

    if response.code.to_i == 200
      Rails.logger.info "Payment bot event published: #{event_type} in room #{room_id}"
      JSON.parse(response.body)["event_id"]
    else
      Rails.logger.error "Payment bot failed to send event: #{response.code} - #{response.body}"
      nil
    end
  rescue => e
    Rails.logger.error "Payment bot error: #{e.message}"
    nil
  end
end
