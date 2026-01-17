class MatrixService
  # Service for interacting with Matrix homeserver as Application Service

  def self.send_message_to_room(room_id, message, event_type = "m.room.message", msgtype = "m.text")
    # Use AS token (not HS token) for Matrix Client-Server API authentication
    # AS token is what the AS uses to authenticate with the homeserver
    as_token = ENV["MATRIX_AS_TOKEN"] || "54280d605e23adf6bd5d66ee07a09196dbab0bd87d35f8ecc1fd70669f709502"

    if as_token.present?
      mas_client = MasClientService.new
      result = mas_client.send_message_to_room(as_token, room_id, message, event_type, msgtype)
      Rails.logger.info "Matrix message send result: #{result.inspect}"
      result
    else
      Rails.logger.error "MATRIX_AS_TOKEN not configured"
      { success: false, error: "auth_error", message: "MATRIX_AS_TOKEN not configured" }
    end
  end

  def self.send_payment_notification(room_id, payment_data)
    message = "💳 Payment completed: $#{payment_data[:amount]} for #{payment_data[:description]}"
    event_content = {
      msgtype: "m.tween.payment",
      body: message,
      payment_id: payment_data[:payment_id],
      amount: payment_data[:amount],
      currency: payment_data[:currency] || "USD",
      status: "completed",
      timestamp: Time.current.to_i
    }

    send_message_to_room(room_id, event_content, "m.tween.payment.completed", "m.tween.payment")
  end

  def self.send_transfer_notification(room_id, transfer_data)
    message = "💸 Transfer completed: $#{transfer_data[:amount]} to #{transfer_data[:recipient_name]}"
    event_content = {
      msgtype: "m.tween.transfer",
      body: message,
      transfer_id: transfer_data[:transfer_id],
      amount: transfer_data[:amount],
      recipient: transfer_data[:recipient_name],
      status: "completed",
      timestamp: Time.current.to_i
    }

    send_message_to_room(room_id, event_content, "m.tween.transfer.completed", "m.tween.transfer")
  end

  private

  def self.get_as_access_token(mas_client)
    # Get access token for Application Service user
    # In production, this would be cached and refreshed as needed
    begin
      token_response = mas_client.client_credentials_grant
      token_response["access_token"]
    rescue => e
      Rails.logger.error "Failed to get AS access token: #{e.message}"
      nil
    end
  end
end
