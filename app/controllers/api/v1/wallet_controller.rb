class Api::V1::WalletController < ApplicationController
  # TMCP Protocol Section 6: Wallet Integration Layer

  before_action :authenticate_tep_token
  before_action :validate_wallet_access, only: [ :balance, :transactions ]
  before_action :validate_user_resolution, only: [ :resolve ]

  # GET /wallet/v1/balance - TMCP Protocol Section 6.2.1
  def balance
    balance_data = WalletService.get_balance(@current_user.matrix_user_id, @tep_token)
    render json: balance_data
  end

  # GET /wallet/v1/transactions - TMCP Protocol Section 6.2.2
  def transactions
    limit = (params[:limit] || 50).to_i.clamp(1, 100)
    offset = (params[:offset] || 0).to_i

    transactions_data = WalletService.get_transactions(@current_user.matrix_user_id, limit: limit, offset: offset, tep_token: @tep_token)
    render json: transactions_data
  end

  # GET /wallet/v1/verification - TMCP Protocol Section 6.4.2
  def verification
    verification_data = WalletService.get_verification_status(@current_user.matrix_user_id)
    render json: verification_data
  end

  # GET /wallet/v1/resolve/:user_id - TMCP Protocol Section 6.3.2
  def resolve
    target_user_id = params[:id]
    resolution_result = WalletService.resolve_user(target_user_id, tep_token: @tep_token)
    render json: resolution_result
  end

  # POST /wallet/v1/resolve/batch - TMCP Protocol Section 6.3.3
  def resolve_batch
    user_ids = params[:user_ids] || []
    room_id = params[:room_id]

    if user_ids.size > 100
      return render json: { error: "too_many_users", message: "Maximum 100 users per batch request" }, status: :bad_request
    end

    results = user_ids.map do |user_id|
      # Check room membership for privacy (TMCP Protocol Section 6.3.7)
      if room_id && !user_in_room?(@current_user.matrix_user_id, user_id, room_id)
        { user_id: user_id, error: { code: "FORBIDDEN", message: "Users do not share a room" } }
      else
        resolution_result = WalletService.resolve_user(user_id)
        resolution_result.merge(user_id: user_id)
      end
    end

    resolved_count = results.count { |r| !r.key?(:error) }
    total_count = results.size

    render json: {
      results: results,
      resolved_count: resolved_count,
      total_count: total_count
    }
  end

  # POST /wallet/v1/p2p/initiate - TMCP Protocol Section 7.2.1
  def initiate_p2p
    # Validate required parameters
    required_params = %w[recipient amount currency idempotency_key]
    missing_params = required_params.select { |param| params[param].blank? }

    if missing_params.any?
      return render json: { error: "invalid_request", message: "Missing required parameters: #{missing_params.join(', ')}" }, status: :bad_request
    end

    # Validate scopes
    unless @token_scopes.include?("wallet:pay")
      return render json: { error: "insufficient_scope", message: "wallet:pay scope required" }, status: :forbidden
    end

    # Validate idempotency key (TMCP Protocol Section 7.2.1)
    cache_key = "p2p_idempotent:#{@current_user.id}:#{params[:idempotency_key]}"
    if Rails.cache.read(cache_key)
      return render json: { error: "duplicate_request", message: "Duplicate request with same idempotency key" }, status: :conflict
    end

    # Validate recipient
    recipient = User.find_by(matrix_user_id: params[:recipient])
    unless recipient
      return render json: { error: { code: "RECIPIENT_NO_WALLET", message: "Recipient does not have a wallet", recipient: params[:recipient], can_invite: true, invite_url: "tween://invite-wallet" } }, status: :not_found
    end

    # Validate room membership
    room_id = params[:room_id]
    if room_id && !user_in_room?(@current_user.matrix_user_id, recipient.matrix_user_id, room_id)
      return render json: { error: "forbidden", message: "Users do not share a room" }, status: :forbidden
    end

    # Create P2P transfer
    transfer_data = WalletService.initiate_p2p_transfer(
      @current_user.wallet_id,
      recipient.wallet_id,
      params[:amount].to_f,
      params[:currency] || "USD",
      sender_user_id: @current_user.matrix_user_id,
      recipient_user_id: recipient.matrix_user_id,
      room_id: room_id
    )

    # Cache idempotency key
    Rails.cache.write(cache_key, transfer_data[:transfer_id], expires_in: 24.hours)

    # Publish Matrix event (PROTO Section 7.2.2)
    MatrixEventService.publish_p2p_transfer(transfer_data)

    render json: transfer_data.merge(
      event_id: "$event_#{transfer_data[:transfer_id]}:tween.example"
    )
  end

  # POST /wallet/v1/p2p/:transfer_id/accept - TMCP Protocol Section 7.2.3
  def accept_p2p
    transfer_id = params[:transfer_id]
    result = WalletService.accept_p2p_transfer(transfer_id, @current_user.wallet_id)

    render json: result
  end

  # POST /wallet/v1/p2p/:transfer_id/reject - TMCP Protocol Section 7.2.3
  def reject_p2p
    transfer_id = params[:transfer_id]
    result = WalletService.reject_p2p_transfer(transfer_id)

    render json: result.merge(
      refund_initiated: true,
      refund_expected_at: (Time.current + 30.seconds).iso8601
    )
  end

  # POST /wallet/v1/external/link - TMCP Protocol Section 6.5.2
  def link_external_account
    account_type = params[:account_type]
    account_details = params[:account_details]

    unless %w[bank_account debit_card credit_card digital_wallet mobile_money].include?(account_type)
      return render json: { error: "invalid_account_type", message: "Unsupported account type" }, status: :bad_request
    end

    result = WalletService.link_external_account(@current_user.wallet_id, account_type, account_details)
    render json: result, status: :created
  end

  # POST /wallet/v1/external/verify - TMCP Protocol Section 6.5.2
  def verify_external_account
    account_id = params[:account_id]
    verification_data = params[:verification_data]

    result = WalletService.verify_external_account(account_id, verification_data)
    render json: result
  end

  # GET /wallet/v1/room/:room_id/members - TMCP Protocol Section 6.3.9
  def room_member_wallets
    room_id = params[:room_id]

    if room_id.blank?
      return render json: { error: "invalid_request", message: "room_id is required" }, status: :bad_request
    end

    # Get room members from Matrix
    member_user_ids = get_room_members(room_id)

    if member_user_ids.empty?
      return render json: { error: "not_found", message: "Room not found or empty" }, status: :not_found
    end

    # Resolve wallets for all members
    wallet_info = member_user_ids.map do |user_id|
      resolution = WalletService.resolve_user(user_id)

      if resolution.key?(:error)
        {
          user_id: user_id,
          has_wallet: false,
          can_invite: true
        }
      else
        verification = WalletService.get_verification_status(user_id)

        {
          user_id: user_id,
          has_wallet: true,
          wallet_id: resolution[:wallet_id],
          verification_level: verification[:level] || 0,
          verification_name: verification[:level_name] || "None"
        }
      end
    end

    render json: {
      room_id: room_id,
      member_count: wallet_info.count { |m| m[:has_wallet] },
      non_wallet_count: wallet_info.count { |m| !m[:has_wallet] },
      members: wallet_info
    }
  end

  private

  def authenticate_tep_token
    auth_header = request.headers["Authorization"]
    unless auth_header&.start_with?("Bearer ")
      return render json: { error: "missing_token", message: "TEP token required" }, status: :unauthorized
    end

    @tep_token = auth_header.sub("Bearer ", "")

    begin
      payload = TepTokenService.decode(@tep_token)
      user_id = payload["sub"]

      @current_user = User.find_by(matrix_user_id: user_id)
      unless @current_user
        return render json: { error: "invalid_token", message: "User not found" }, status: :unauthorized
      end

      @token_scopes = payload["scope"]&.split(" ") || []
    rescue JWT::DecodeError => e
      render json: { error: "invalid_token", message: e.message }, status: :unauthorized
    end
  end

  def validate_wallet_access
    unless @token_scopes.include?("wallet:balance")
      render json: { error: "insufficient_scope", message: "wallet:balance scope required" }, status: :forbidden
    end
  end

  def validate_user_resolution
    unless @token_scopes.include?("wallet:pay") || @token_scopes.include?("wallet:balance")
      render json: { error: "insufficient_scope", message: "wallet scope required for user resolution" }, status: :forbidden
    end
  end

  def user_in_room?(user1, user2, room_id)
    # Mock room membership validation
    # In production, query Matrix homeserver
    true # Simplified for demo
  end

  def get_room_members(room_id)
    # Mock room members - in production, query Matrix homeserver
    # Returns array of Matrix user IDs
    [ "@alice:tween.example", "@bob:tween.example", "@charlie:tween.example" ]
  end
end
