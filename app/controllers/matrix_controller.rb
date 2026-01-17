class MatrixController < ApplicationController
  # TMCP Protocol Section 3.1.2: Matrix Application Service

  skip_before_action :verify_authenticity_token
  before_action :verify_as_token, only: [ :transactions, :ping, :thirdparty_location, :thirdparty_user, :thirdparty_location_protocol, :thirdparty_user_protocol ]

  # PUT /_matrix/app/v1/transactions/:txn_id - Handle Matrix events
  def transactions
    txn_id = params[:txn_id]

    # Process each event in transaction
    events = params[:events] || []

    events.each do |event|
      process_matrix_event(event)
    end

    # Acknowledge transaction
    render json: {}, status: :ok
  end

  # GET /_matrix/app/v1/users/:user_id - Query user existence
  def user
    begin
      user_id = CGI.unescape(params[:user_id])

      Rails.logger.debug "MatrixController#user: params[:user_id]=#{params[:user_id].inspect}, unescaped=#{user_id.inspect}"

      # Check if user exists in our system
      user = User.find_by(matrix_user_id: user_id)

      # Also check if this is a TMCP bot user (virtual users owned by AS)
      is_tmcp_bot = user_id.start_with?("@_tmcp") || user_id.start_with?("@ma_")

      Rails.logger.debug "MatrixController#user: found user=#{user.inspect}, is_tmcp_bot=#{is_tmcp_bot}"

      # Matrix AS spec: Return empty body with 200 if user exists, 404 if not
      if user || is_tmcp_bot
        render json: {}, status: :ok
      else
        render json: {}, status: :not_found
      end
    rescue => e
      Rails.logger.error "MatrixController#user error: #{e.message}"
      render json: {}, status: :not_found
    end
  end

  # GET /_matrix/app/v1/rooms/:room_alias - Query room alias
  def room
    room_alias = params[:room_alias]

    # Check if room alias exists (simplified)
    # In production, would check against configured rooms
    if room_alias.start_with?("#_tmcp")
      render json: {}, status: :ok
    else
      render json: {}, status: :not_found
    end
  end

  # GET /_matrix/app/v1/ping - Ping endpoint for AS health check
  def ping
    render json: {}, status: :ok
  end

  # GET /_matrix/app/v1/thirdparty/location - Get third-party location protocols
  def thirdparty_location
    # Return available third-party location protocols
    # For TMCP, this could include mini-app locations or wallet service locations
    render json: [], status: :ok
  end

  # GET /_matrix/app/v1/thirdparty/user - Get third-party user protocols
  def thirdparty_user
    # Return available third-party user protocols
    # For TMCP, this could include user bridging to external services
    render json: [], status: :ok
  end

  # GET /_matrix/app/v1/thirdparty/location/:protocol - Query locations for protocol
  def thirdparty_location_protocol
    protocol = params[:protocol]

    # Return locations for specified protocol
    # TMCP doesn't define specific third-party protocols yet
    render json: [], status: :ok
  end

  # GET /_matrix/app/v1/thirdparty/user/:protocol - Query users for protocol
  def thirdparty_user_protocol
    protocol = params[:protocol]

    # Return users for specified protocol
    # TMCP doesn't define specific third-party protocols yet
    render json: [], status: :ok
  end

  # POST /api/v1/internal/matrix/invite_as_direct - Direct AS invitation (bypasses room restrictions)
  # Uses AS token directly to invite AS to rooms with restrictive settings
  # Automatically called by P2P payment flow to ensure AS can send notifications
  # This bypasses room member permissions that block normal invitations
  def invite_as_direct
    room_id = params[:room_id]

    unless room_id.present?
      return render json: { error: "invalid_request", message: "room_id is required" }, status: :bad_request
    end

    unless room_id.match?(/^![A-Za-z0-9]+:.+/)
      return render json: { error: "invalid_request", message: "Invalid room_id format" }, status: :bad_request
    end

    # Direct AS invitation using AS token (bypasses room member restrictions)
    invite_result = MatrixService.invite_as_direct(room_id)

    if invite_result[:success]
      render json: {
         success: true,
         room_id: room_id,
         invited_user: invite_result[:user_id],
         method: "direct_as_token",
         message: "TMCP AS directly invited to room. AS can now send notifications."
      }
    else
      render json: {
        error: "invite_failed",
        message: invite_result[:message] || "Failed to directly invite AS to room"
      }, status: :bad_request
    end
  end

  # POST /api/v1/internal/matrix/send_test_message - Send test message (for testing)
  def send_test_message
    room_id = params[:room_id]
    message = params[:message] || "Test message from TMCP"

    unless room_id.present?
      return render json: { error: "invalid_request", message: "room_id is required" }, status: :bad_request
    end

    unless room_id.match?(/^![A-Za-z0-9]+:.+/)
      return render json: { error: "invalid_request", message: "Invalid room_id format" }, status: :bad_request
    end

    # Send message to room
    message_result = MatrixService.send_message_to_room(room_id, message)

    if message_result[:success]
      render json: {
        success: true,
        room_id: room_id,
        event_id: message_result[:event_id],
        message: "Test message sent successfully"
      }
    else
      render json: {
        error: "send_failed",
        message: message_result[:message] || "Failed to send test message"
      }, status: :bad_request
    end
  end

  private

  def verify_as_token
    # Verify AS token from Matrix homeserver
    auth_header = request.headers["Authorization"]

    # Extract token from "Bearer {token}" format (case-insensitive)
    provided_token = auth_header&.sub(/^Bearer\s+/i, "")

    expected_token = ENV["MATRIX_HS_TOKEN"] # Token we registered with homeserver

    unless provided_token == expected_token
      Rails.logger.warn "Matrix AS authentication failed: provided_token=#{provided_token&.first(10)}..., expected_token=#{expected_token&.first(10)}..."
      render json: { error: "unauthorized" }, status: :unauthorized
      nil
    end
  end

  def process_matrix_event(event)
    event_type = event["type"]
    room_id = event["room_id"]
    sender = event["sender"]
    content = event["content"]

    case event_type
    when "m.room.message"
      handle_room_message(room_id, sender, content)
    when "m.room.member"
      handle_room_member(room_id, sender, content)
    else
      # Log unknown event types for debugging
      Rails.logger.info "Received unknown Matrix event type: #{event_type}"
    end
  rescue => e
    Rails.logger.error "Error processing Matrix event #{event_type}: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
  end

  def handle_room_message(room_id, sender, content)
    msgtype = content["msgtype"]
    body = content["body"]

    Rails.logger.info "Matrix message in room #{room_id} from #{sender}: #{msgtype} - #{body}"

    # Handle text messages - could be commands or interactions
    if msgtype == "m.text"
      handle_text_message(room_id, sender, body)
    else
      Rails.logger.debug "Unhandled message type: #{msgtype}"
    end
  end

  def handle_room_member(room_id, sender, content)
    membership = content["membership"]
    user_id = content["state_key"] || sender

    case membership
    when "invite"
      # Someone invited a user to the room
      handle_user_invite(room_id, sender, user_id)
    when "join"
      # User joined room - could trigger wallet resolution or app notifications
      handle_user_join(room_id, user_id)
    when "leave"
      # User left room - cleanup if needed
      handle_user_leave(room_id, user_id)
    end
  end

  def handle_text_message(room_id, sender, body)
    # Check for TMCP-related commands or mentions
    if body.include?("@tmcp") || body.include?("!wallet") || body.include?("!pay")
      # Could trigger mini-app launches or payment flows
      Rails.logger.info "TMCP command detected in room #{room_id} from #{sender}: #{body}"
    end
  end

  def handle_user_invite(room_id, sender, invited_user_id)
    Rails.logger.info "User #{invited_user_id} invited to room #{room_id} by #{sender}"

    # Auto-join if we're invited (AS users: @_tmcp:tween.im or @_tmcp_payments:tween.im)
    if invited_user_id == "@_tmcp:tween.im" || invited_user_id == "@_tmcp_payments:tween.im"
      Rails.logger.info "TMCP AS user #{invited_user_id} invited to room #{room_id} - auto-joining..."
      join_result = MatrixService.join_room_as_user(room_id, invited_user_id)

      if join_result[:success]
        Rails.logger.info "TMCP AS user #{invited_user_id} successfully auto-joined room #{room_id}"
      else
        Rails.logger.error "TMCP AS user #{invited_user_id} failed to auto-join room #{room_id}: #{join_result[:message]}"
      end
    end
  end

  def handle_user_join(room_id, user_id)
    Rails.logger.info "User #{user_id} joined room #{room_id}"

    # If it's our AS user joining, log it
    if user_id == "@_tmcp:tween.im"
      Rails.logger.info "TMCP AS user joined room #{room_id} - ready for notifications"
    end
  end

  def handle_user_leave(room_id, user_id)
    # User left room - cleanup room-specific data
    Rails.logger.info "User #{user_id} left room #{room_id}"
  end
end
