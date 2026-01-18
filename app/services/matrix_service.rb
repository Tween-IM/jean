class MatrixService
  # Service for interacting with Matrix homeserver as Application Service

  def self.ensure_as_in_room(room_id, user_token = nil, as_user = "@_tmcp:tween.im")
    # Ensure AS user is in the room
    # Strategy: Invite AS user using provided user token, then AS will auto-join via webhook
    # For payments, use @_tmcp_payments:tween.im (PROTO.md Section 7.3.2)

    as_user_id = as_user

    # First, try to join directly (works for AS-created rooms)
    join_result = join_room_as_as(room_id)
    if join_result[:success]
      Rails.logger.info "AS joined room directly: #{room_id}"
      return join_result
    end

    # If direct join failed, invite the AS user to the room
    if user_token
      invite_result = invite_as_to_room(room_id, user_token)
      if invite_result[:success]
        Rails.logger.info "AS invited to room: #{room_id}"
        # AS should auto-join via Matrix webhook when invited
        return { success: true, invited: true, user_id: as_user_id, message: "AS invited, will auto-join" }
      else
        Rails.logger.warn "Failed to invite AS to room: #{invite_result[:message]}"
      end
    end

    { success: false, error: "cannot_access_room", message: "AS cannot join room and no user token to invite" }
  end

  def self.invite_as_to_room(room_id, user_token)
    # Invite @_tmcp:tween.im to the room using user's Matrix token
    as_user_id = "@_tmcp:tween.im"
    homeserver_url = ENV["MATRIX_API_URL"] || "https://core.tween.im"

    mas_client = MasClientService.new
    response = mas_client.send(:http_client).post("#{homeserver_url}/_matrix/client/v3/rooms/#{CGI.escape(room_id)}/invite") do |req|
      req.headers["Authorization"] = "Bearer #{user_token}"
      req.headers["Content-Type"] = "application/json"
      req.body = { user_id: as_user_id }.to_json
    end

    if response.success?
      Rails.logger.info "Successfully invited AS user #{as_user_id} to room #{room_id}"
      { success: true, invited: true, user_id: as_user_id }
    else
      Rails.logger.error "Failed to invite AS to room #{room_id}: #{response.status} - #{response.body}"
      { success: false, error: response.status, message: response.body }
    end
  end

  # Manual API endpoint for inviting AS to rooms (for testing and manual use cases)
  def self.invite_as_direct(room_id, as_token = nil)
    # Direct AS invitation using AS token (bypasses room member restrictions)
    # This is called by invite_as_direct controller when AS needs to invite itself to rooms
    # Useful for rooms with restrictive settings that block normal user invitations

    as_token = ENV["MATRIX_AS_TOKEN"]
    unless as_token
      Rails.logger.error "MATRIX_AS_TOKEN not configured"
      return { success: false, error: "auth_error", message: "MATRIX_AS_TOKEN not configured" }
    end

    as_user_id = "@_tmcp:tween.im"
    homeserver_url = ENV["MATRIX_API_URL"] || "https://core.tween.im"

    mas_client = MasClientService.new
    response = mas_client.send(:http_client).post("#{homeserver_url}/_matrix/client/v3/rooms/#{CGI.escape(room_id)}/invite") do |req|
      req.headers["Authorization"] = "Bearer #{as_token}"
      req.headers["Content-Type"] = "application/json"
      req.body = { user_id: as_user_id }.to_json
    end

    if response.success?
      Rails.logger.info "Successfully invited AS user #{as_user_id} to room #{room_id} via direct AS token"
      { success: true, invited: true, user_id: as_user_id }
    else
      Rails.logger.error "Failed to invite AS user #{as_user_id} to room #{room_id}: #{response.status} - #{response.body}"
      { success: false, error: response.status, message: response.body }
    end
  end

  def self.join_room_as_user(room_id, user_id)
    # Join room directly as specified AS user (works for AS-created rooms or when invited)
    as_token = ENV["MATRIX_AS_TOKEN"]
    unless as_token
      Rails.logger.error "MATRIX_AS_TOKEN not configured"
      return { success: false, error: "auth_error", message: "MATRIX_AS_TOKEN not configured" }
    end

    mas_client = MasClientService.new
    homeserver_url = ENV["MATRIX_API_URL"] || "https://core.tween.im"

    response = mas_client.send(:http_client).put("#{homeserver_url}/_matrix/client/v3/rooms/#{CGI.escape(room_id)}/join/#{CGI.escape(user_id)}") do |req|
      req.headers["Authorization"] = "Bearer #{as_token}"
      req.headers["Content-Type"] = "application/json"
      req.body = {}.to_json
    end

    if response.success?
      Rails.logger.info "AS successfully joined room #{room_id} as #{user_id}"
      { success: true, joined: true, user_id: user_id }
    else
      Rails.logger.error "AS failed to join room #{room_id} as #{user_id}: #{response.status} - #{response.body}"
      { success: false, error: response.status, message: response.body }
    end
  end

  def self.join_room_as_as(room_id)
    # Legacy method - join as main AS user
    join_room_as_user(room_id, "@_tmcp:tween.im")
  end

  def self.join_room(room_id)
    # Application Services have "server admin style permissions"
    # They can join any room without invitation using their AS token
    # See: https://spec.matrix.org/v1.17/application-service-api/#server-admin-style-permissions

    as_token = ENV["MATRIX_AS_TOKEN"]
    unless as_token
      Rails.logger.error "MATRIX_AS_TOKEN not configured"
      return { success: false, error: "auth_error", message: "MATRIX_AS_TOKEN not configured" }
    end

    as_user_id = "@_tmcp:tween.im"
    mas_client = MasClientService.new
    homeserver_url = ENV["MATRIX_API_URL"] || "https://core.tween.im"

    # AS can join any room directly without invitation using server admin permissions
    response = mas_client.send(:http_client).put("#{homeserver_url}/_matrix/client/v3/rooms/#{CGI.escape(room_id)}/join/#{CGI.escape(as_user_id)}") do |req|
      req.headers["Authorization"] = "Bearer #{as_token}"
      req.headers["Content-Type"] = "application/json"
      req.body = {}.to_json
    end

    if response.success?
      Rails.logger.info "AS successfully joined room #{room_id} as #{as_user_id}"
      { success: true, joined: true, user_id: as_user_id }
    else
      Rails.logger.error "AS failed to join room #{room_id}: #{response.status} - #{response.body}"
      { success: false, error: response.status, message: response.body }
    end
  end

  def self.send_message_to_room(room_id, message, event_type = "m.room.message", msgtype = "m.text", user_token = nil, as_user = "@_tmcp:tween.im")
    # Use AS token (not HS token) for Matrix Client-Server API authentication
    as_token = ENV["MATRIX_AS_TOKEN"]
    unless as_token
      Rails.logger.error "MATRIX_AS_TOKEN not configured"
      return { success: false, error: "auth_error", message: "MATRIX_AS_TOKEN not configured" }
    end

    mas_client = MasClientService.new
    # MasClientService.send_message_to_room now handles room joining internally
    # Pass user_token as user_id if provided (for mini-app users), otherwise use specified as_user
    user_id = user_token ? "@_tmcp:tween.im" : as_user
    result = mas_client.send_message_to_room(as_token, room_id, message, event_type, msgtype, user_id)
    Rails.logger.info "Matrix message send result: #{result.inspect}"
    result
  end

  def self.send_payment_notification(room_id, payment_data)
    # PROTO.md Section 4.11.2 specifies @_tmcp_payments:tween.im for payments
    # Note: Requires separate AS registration with sender_localpart: _tmcp_payments
    # Currently using main AS user until payment bot registration is configured
    payment_user = "@_tmcp:tween.im"

    # Ensure AS user is in the room
    ensure_result = ensure_as_in_room(room_id, nil, payment_user)
    unless ensure_result[:success]
      Rails.logger.warn "Failed to ensure payment AS user in room: #{ensure_result[:message]}"
    end

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

    # Send as payment user
    send_message_to_room(room_id, event_content, "m.tween.payment.completed", "m.tween.payment", nil, payment_user)
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

  def self.create_room(name, topic = nil, is_public = false)
    # Create a room using Matrix Client-Server API
    as_token = ENV["MATRIX_AS_TOKEN"]
    unless as_token
      Rails.logger.error "MATRIX_AS_TOKEN not configured"
      return { success: false, error: "auth_error", message: "MATRIX_AS_TOKEN not configured" }
    end

    mas_client = MasClientService.new
    homeserver_url = ENV["MATRIX_API_URL"] || "https://core.tween.im"

    # Use the same HTTP client as MasClientService
    response = mas_client.send(:http_client).post("#{homeserver_url}/_matrix/client/v3/createRoom") do |req|
      req.headers["Authorization"] = "Bearer #{as_token}"
      req.headers["Content-Type"] = "application/json"
      req.body = {
        name: name,
        topic: topic,
        visibility: is_public ? "public" : "private",
        preset: "private_chat",
        is_direct: false
      }.compact.to_json
    end

    if response.success?
      result = JSON.parse(response.body)
      room_id = result["room_id"]
      Rails.logger.info "Matrix room created successfully: #{room_id}"
      { success: true, room_id: room_id }
    else
      Rails.logger.error "Failed to create Matrix room: #{response.status} - #{response.body}"
      { success: false, error: response.status, message: response.body }
    end
  end

  def self.register_as_user(user_id)
    # Register an AS user with Matrix homeserver using m.login.application_service
    # Per Matrix spec, AS MUST create users when returning 200 to /users/{userId} endpoint
    as_token = ENV["MATRIX_AS_TOKEN"]
    unless as_token
      Rails.logger.error "MATRIX_AS_TOKEN not configured"
      return { success: false, error: "auth_error", message: "MATRIX_AS_TOKEN not configured" }
    end

    # Extract localpart from user_id (e.g., @_tmcp:tween.im -> _tmcp)
    localpart = user_id.split(":").first&.sub(/^@/, "")
    unless localpart
      Rails.logger.error "Invalid user_id format: #{user_id}"
      return { success: false, error: "invalid_user_id", message: "Invalid user_id format" }
    end

    mas_client = MasClientService.new
    homeserver_url = ENV["MATRIX_API_URL"] || "https://core.tween.im"

    # Register user using m.login.application_service
    response = mas_client.send(:http_client).post("#{homeserver_url}/_matrix/client/v3/register") do |req|
      req.headers["Authorization"] = "Bearer #{as_token}"
      req.headers["Content-Type"] = "application/json"
      req.body = {
        type: "m.login.application_service",
        username: localpart
      }.to_json
    end

    if response.success?
      Rails.logger.info "Successfully registered AS user #{user_id}"
      { success: true, user_id: user_id }
    elsif response.status == 400
      # Check if user already exists
      error_data = JSON.parse(response.body) rescue {}
      if error_data["errcode"] == "M_USER_IN_USE"
        Rails.logger.info "AS user #{user_id} already exists, treating as success"
        { success: true, user_id: user_id, already_exists: true }
      else
        Rails.logger.error "Failed to register AS user #{user_id}: #{response.status} - #{response.body}"
        { success: false, error: response.status, message: response.body }
      end
    else
      Rails.logger.error "Failed to register AS user #{user_id}: #{response.status} - #{response.body}"
      { success: false, error: response.status, message: response.body }
    end
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
