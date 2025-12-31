class MatrixController < ApplicationController
  # TMCP Protocol Section 3.1.2: Matrix Application Service

  skip_before_action :verify_authenticity_token
  before_action :verify_as_token

  # POST /_matrix/app/v1/transactions/:txn_id - Handle Matrix events
  def transactions
    txn_id = params[:txn_id]

    # Process each event in the transaction
    events = params[:events] || []

    events.each do |event|
      process_matrix_event(event)
    end

    # Acknowledge transaction
    render json: {}, status: :ok
  end

  # GET /_matrix/app/v1/users/:user_id - Query user existence
  def user
    user_id = CGI.unescape(params[:user_id])

    Rails.logger.debug "MatrixController#user: params[:user_id]=#{params[:user_id].inspect}, unescaped=#{user_id.inspect}"

    # Check if user exists in our system
    user = User.find_by(matrix_user_id: user_id)

    Rails.logger.debug "MatrixController#user: found user=#{user.inspect}"

    if user
      render json: {}, status: :ok
    else
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

    # Return locations for the specified protocol
    # TMCP doesn't define specific third-party protocols yet
    render json: [], status: :ok
  end

  # GET /_matrix/app/v1/thirdparty/user/:protocol - Query users for protocol
  def thirdparty_user_protocol
    protocol = params[:protocol]

    # Return users for the specified protocol
    # TMCP doesn't define specific third-party protocols yet
    render json: [], status: :ok
  end

  private

  def verify_as_token
    # Verify the AS token from Matrix homeserver
    auth_header = request.headers["Authorization"]
    provided_token = auth_header&.sub("Bearer ", "")

    expected_token = ENV["MATRIX_HS_TOKEN"] # Token we registered with homeserver

    unless provided_token == expected_token
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
    Rails.logger.error "Error processing Matrix event: #{e.message}"
  end

  def handle_room_message(room_id, sender, content)
    msgtype = content["msgtype"]
    body = content["body"]

    case msgtype
    when "m.text"
      # Handle text messages - could be commands or interactions
      handle_text_message(room_id, sender, body)
    else
      Rails.logger.debug "Unhandled message type: #{msgtype}"
    end
  end

  def handle_room_member(room_id, sender, content)
    membership = content["membership"]
    user_id = content["state_key"] || sender

    case membership
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

  def handle_user_join(room_id, user_id)
    # User joined room - could auto-resolve wallet status
    Rails.logger.info "User #{user_id} joined room #{room_id}"

    # In production, could trigger wallet status updates or notifications
  end

  def handle_user_leave(room_id, user_id)
    # User left room - cleanup room-specific data
    Rails.logger.info "User #{user_id} left room #{room_id}"
  end
end
