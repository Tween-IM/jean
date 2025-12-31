class Api::V1::PaymentsController < ApplicationController
  # TMCP Protocol Section 7.3-7.4: Mini-App Payment Processing with MFA

  before_action :authenticate_tep_token
  before_action :validate_payment_scope, only: [ :create, :authorize, :refund ]

  # POST /api/v1/payments/request - TMCP Protocol Section 7.3.1
  def create
    raw_params = request.parameters

    # Validate required TMCP parameters (Section 7.3.1)
    required_params = %w[amount currency description merchant_order_id callback_url]
    missing_params = required_params.select { |param| raw_params[param].blank? }

    if missing_params.any?
      return render json: { error: "invalid_request", message: "Missing required parameters: #{missing_params.join(', ')}" }, status: :bad_request
    end

    # Validate amount
    amount = raw_params[:amount].to_f
    if amount <= 0 || amount > 50000.00 # TMCP transaction limit
      return render json: { error: "invalid_amount", message: "Amount must be between 0.01 and 50,000.00" }, status: :bad_request
    end

    # Validate currency
    currency = raw_params[:currency].to_s.upcase
    unless %w[USD EUR GBP].include?(currency) # TMCP supported currencies
      return render json: { error: "invalid_currency", message: "Unsupported currency: #{currency}" }, status: :bad_request
    end

    # Validate callback URL format
    callback_url = raw_params[:callback_url]
    begin
      uri = URI.parse(callback_url)
      unless uri.scheme == "https"
        return render json: { error: "invalid_callback_url", message: "Callback URL must use HTTPS" }, status: :bad_request
      end
    rescue URI::InvalidURIError
      return render json: { error: "invalid_callback_url", message: "Invalid callback URL format" }, status: :bad_request
    end

    # Validate merchant_order_id format
    merchant_order_id = raw_params[:merchant_order_id].to_s
    unless merchant_order_id.match?(/\A[A-Z0-9\-_]{1,100}\z/)
      return render json: { error: "invalid_merchant_order_id", message: "Merchant order ID must be 1-100 alphanumeric characters, hyphens, or underscores" }, status: :bad_request
    end

    # Validate optional items array if provided
    if raw_params[:items].present?
      unless raw_params[:items].is_a?(Array)
        return render json: { error: "invalid_items", message: "Items must be an array" }, status: :bad_request
      end

      raw_params[:items].each do |item|
        unless item.is_a?(Hash) && item["item_id"].present? && item["name"].present? && item["quantity"].present? && item["unit_price"].present?
          return render json: { error: "invalid_item", message: "Each item must have item_id, name, quantity, and unit_price" }, status: :bad_request
        end
      end
    end

    # Extract validated parameters
    description = raw_params[:description].to_s
    items = raw_params[:items] || []

    # Check if MFA is required (TMCP Protocol Section 7.4)
    mfa_required = amount > 50.00 # Configurable threshold

    # Create payment request
    payment_data = WalletService.create_payment_request(
      @current_user.wallet_id,
      "tw_merchant_demo", # Mock merchant wallet
      amount,
      currency,
      description,
      miniapp_id: "ma_shop_001",
      merchant_order_id: merchant_order_id,
      items: items,
      callback_url: callback_url
    )

    # Cache payment data (TMCP requires idempotency)
    payment_cache_key = "payment:#{payment_data[:payment_id]}"
    Rails.cache.write(payment_cache_key, payment_data.except(:event_id), expires_in: 5.minutes)

    render json: payment_data, status: :created
  end

  # POST /api/v1/payments/:payment_id/authorize - TMCP Protocol Section 7.3.2
  def authorize
    raw_params = request.request_parameters.to_h
    payment_id = raw_params["payment_id"]
    payment_data = Rails.cache.read("payment:#{payment_id}")

    unless payment_data
      return render json: { error: "invalid_payment", message: "Payment request not found or expired" }, status: :not_found
    end

    # Verify payment belongs to current user
    unless payment_data["user_id"] == @current_user.matrix_user_id
      return render json: { error: "unauthorized", message: "Payment does not belong to current user" }, status: :forbidden
    end

    # Check if MFA is required and validate
    if payment_data["mfa_required"]
      handle_mfa_authorization(payment_id, payment_data)
    else
      complete_payment_authorization(payment_id, payment_data)
    end
  end

  # POST /api/v1/payments/:payment_id/refund - TMCP Protocol Section 7.4
  def refund
    raw_params = request.request_parameters.to_h
    payment_id = raw_params["payment_id"]
    payment_data = Rails.cache.read("payment:#{payment_id}")

    unless payment_data
      return render json: { error: "payment_not_found", message: "Payment not found" }, status: :not_found
    end

    unless payment_data["status"] == "completed"
      return render json: { error: "invalid_status", message: "Only completed payments can be refunded" }, status: :bad_request
    end

    amount = raw_params["amount"]&.to_f || payment_data["amount"]
    if amount > payment_data["amount"]
      return render json: { error: "invalid_amount", message: "Refund amount cannot exceed payment amount" }, status: :bad_request
    end

    # Process refund with WalletService
    refund_result = WalletService.refund_payment(payment_id, amount, raw_params["reason"] || "customer_request")

    render json: refund_result.merge(
      refunded_at: Time.current.iso8601
    )
  end

  # POST /api/v1/payments/:payment_id/mfa/challenge - TMCP Protocol Section 7.4.2
  def mfa_challenge
    raw_params = request.request_parameters.to_h
    payment_id = raw_params["payment_id"]
    payment_data = Rails.cache.read("payment:#{payment_id}")

    unless payment_data && payment_data["mfa_required"]
      return render json: { error: "mfa_not_required", message: "MFA not required for this payment" }, status: :bad_request
    end

    # Get MFA challenge from WalletService
    mfa_challenge = WalletService.request_mfa_challenge(payment_id, @current_user.matrix_user_id)

    # Cache challenge
    Rails.cache.write("mfa_challenge:#{mfa_challenge[:challenge_id]}", mfa_challenge, expires_in: 3.minutes)

    render json: {
      payment_id: payment_id,
      status: "mfa_required",
      mfa_challenge: mfa_challenge
    }, status: :payment_required
  end

  # POST /api/v1/payments/:payment_id/mfa/verify - TMCP Protocol Section 7.4.3
  def mfa_verify
    raw_params = request.request_parameters.to_h
    challenge_id = raw_params["challenge_id"]
    challenge_data = Rails.cache.read("mfa_challenge:#{challenge_id}")

    unless challenge_data
      return render json: { error: "invalid_challenge", message: "MFA challenge not found or expired" }, status: :not_found
    end

    method = raw_params["method"]
    credentials = raw_params["credentials"]

    unless %w[transaction_pin biometric totp].include?(method)
      return render json: { error: "invalid_method", message: "Unsupported MFA method" }, status: :bad_request
    end

    # Verify MFA with WalletService
    verification_result = WalletService.verify_mfa_response(challenge_id, method, credentials)

    if verification_result[:status] == "verified"
      # Proceed with payment authorization
      payment_data = Rails.cache.read("payment:#{challenge_data['payment_id']}")
      complete_payment_authorization(challenge_data["payment_id"], payment_data)
    else
      render json: {
        payment_id: challenge_data["payment_id"],
        challenge_id: challenge_id,
        status: "failed",
        error: verification_result[:error]
      }, status: :unauthorized
    end
  end

  private

  def authenticate_tep_token
    auth_header = request.headers["Authorization"]
    unless auth_header&.start_with?("Bearer ")
      return render json: { error: "missing_token", message: "TEP token required" }, status: :unauthorized
    end

    token = auth_header.sub("Bearer ", "")

    begin
      payload = TepTokenService.decode(token)
      user_id = payload["sub"]

      @current_user = User.find_by(matrix_user_id: user_id)
      Rails.logger.debug "Authenticating user: #{user_id}, found: #{@current_user.inspect}"
      unless @current_user
        return render json: { error: "invalid_token", message: "User not found" }, status: :unauthorized
      end

      @token_scopes = payload["scope"]&.split(" ") || []
    rescue JWT::DecodeError => e
      render json: { error: "invalid_token", message: e.message }, status: :unauthorized
    end
  end

  def validate_payment_scope
    unless @token_scopes.include?("wallet:pay")
      render json: { error: "insufficient_scope", message: "wallet:pay scope required" }, status: :forbidden
    end
  end

  def handle_mfa_authorization(payment_id, payment_data)
    # Initiate MFA challenge
    challenge_id = "mfa_#{SecureRandom.alphanumeric(12)}"

    mfa_challenge = {
      challenge_id: challenge_id,
      payment_id: payment_id,
      methods: [
        {
          type: "transaction_pin",
          enabled: true,
          display_name: "Transaction PIN"
        }
      ],
      required_method: "any",
      expires_at: (Time.current + 3.minutes).iso8601,
      max_attempts: 3
    }

    Rails.cache.write("mfa_challenge:#{challenge_id}", mfa_challenge, expires_in: 3.minutes)

    render json: {
      payment_id: payment_id,
      status: "mfa_required",
      mfa_challenge: mfa_challenge
    }, status: :payment_required
  end

  def complete_payment_authorization(payment_id, payment_data)
    # Mock payment completion (in production, call Wallet Service)
    txn_id = "txn_#{SecureRandom.alphanumeric(12)}"

    # Authorize payment
    auth_result = WalletService.authorize_payment(
      payment_id,
      params[:signature],
      device_id: params[:device_id],
      timestamp: params[:timestamp]
    )

    # Update cached payment data
    payment_data.merge!(auth_result)
    Rails.cache.write("payment:#{payment_id}", payment_data, expires_in: 24.hours)

    # Publish Matrix event (PROTO Section 8.1.2)
    MatrixEventService.publish_payment_completed({
      payment_id: payment_id,
      txn_id: auth_result["txn_id"],
      amount: payment_data["amount"],
      currency: payment_data["currency"],
      merchant: {
        miniapp_id: payment_data["merchant"]["miniapp_id"],
        name: payment_data["merchant"]["name"]
      },
      user_id: @current_user.matrix_user_id
    })

    render json: {
      payment_id: payment_id,
      status: auth_result["status"],
      txn_id: auth_result["txn_id"],
      amount: payment_data["amount"],
      payer: {
        user_id: @current_user.matrix_user_id,
        wallet_id: @current_user.wallet_id
      },
      merchant: payment_data["merchant"],
      completed_at: auth_result["completed_at"]
    }
  end
end
