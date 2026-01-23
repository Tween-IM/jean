class WalletService
  # TMCP Protocol Section 6: Real Wallet Service Integration
  # Integrated with Tween Pay API at https://wallettween.im

  class WalletError < StandardError; end

  # Circuit breakers for different operations (PROTO Section 7.7)
  @@circuit_breakers = {
    balance: CircuitBreakerService.new("wallet_balance"),
    payments: CircuitBreakerService.new("wallet_payments"),
    transfers: CircuitBreakerService.new("wallet_transfers"),
    verification: CircuitBreakerService.new("wallet_verification")
  }

  # Configuration from initializer
  WALLET_API_BASE_URL = ENV.fetch("WALLET_API_BASE_URL", "https://wallet.tween.im")
  WALLET_API_KEY = ENV.fetch("WALLET_API_KEY", "")

  def self.make_wallet_request(method, endpoint, body = nil, headers = {})
    url = "#{WALLET_API_BASE_URL}#{endpoint}"

    default_headers = {
      "Content-Type" => "application/json",
      "Accept" => "application/json"
    }

    if WALLET_API_KEY.present?
      default_headers["Authorization"] = "Bearer #{WALLET_API_KEY}"
    end

    headers.merge!(default_headers)

    begin
      response = case method.to_sym
      when :get
                   Faraday.get(url, nil, headers)
      when :post
                   Faraday.post(url, body&.to_json, headers)
      when :put
                   Faraday.put(url, body&.to_json, headers)
      when :delete
                   Faraday.delete(url, nil, headers)
      else
                   raise "Unsupported HTTP method: #{method}"
      end

      unless response.success?
        Rails.logger.error "Wallet API error: #{response.status} - #{response.body}"
        raise WalletError.new("Wallet service unavailable (HTTP #{response.status})")
      end

      JSON.parse(response.body)
    rescue Faraday::Error => e
      Rails.logger.error "Wallet API connection error: #{e.message}"
      raise WalletError.new("Wallet service unavailable")
    rescue JSON::ParserError => e
      Rails.logger.error "Wallet API response parsing error: #{e.message}"
      raise WalletError.new("Invalid wallet service response")
    end
  end

  def self.ensure_user_registered(matrix_user_id, tep_token)
    return if tep_token.blank?

    begin
      # Try to register the user in wallet service
      register_response = make_wallet_request(:post, "/api/v1/tmcp/wallets/register",
                                            { user_id: matrix_user_id, currency: "NGN" },
                                            { "Authorization" => "Bearer #{tep_token}" })

      Rails.logger.info "Auto-registered user #{matrix_user_id} in wallet service during TEP token issuance"
    rescue WalletError => e
      # If registration fails, log but don't block TEP token issuance
      Rails.logger.warn "Failed to auto-register user #{matrix_user_id} in wallet service: #{e.message}"
    end
  end

  def self.get_balance(user_id, tep_token = nil)
    @@circuit_breakers[:balance].call do
      Rails.logger.info "Getting balance for user #{user_id}"

      # Call tween-pay TMCP balance endpoint
      response = make_wallet_request(:get, "/api/v1/tmcp/wallets/balance",
                                   nil, { "Authorization" => "Bearer #{tep_token}" })

      if response.success?
        data = JSON.parse(response.body).symbolize_keys

        # Transform response to match jean's expected format
        {
          wallet_id: data[:wallet_id],
          balance: {
            available: data.dig(:balance, :available) || 0.00,
            pending: data.dig(:balance, :pending) || 0.00,
            currency: data.dig(:balance, :currency) || "USD"
          },
          limits: data[:limits] || {
            daily_limit: 1000.00,
            daily_used: 0.00,
            transaction_limit: 500.00
          },
          verification: data[:verification] || {
            level: 0,
            level_name: "Unverified",
            features: [],
            can_upgrade: true,
            next_level: 1,
            upgrade_requirements: [ "id_verification" ]
          },
          status: data[:status] || "active"
        }
      else
        Rails.logger.error "Wallet balance API error: #{response.status} - #{response.body}"
        raise WalletError.new("Failed to get balance from wallet service")
      end
    end
  end

  def self.get_transactions(user_id, limit: 50, offset: 0, tep_token: nil)
    @@circuit_breakers[:balance].call do
      Rails.logger.info "Getting transactions for user #{user_id}"

      # Call tween-pay TMCP transactions endpoint
      response = make_wallet_request(:get, "/api/v1/tmcp/wallet/transactions?limit=#{limit}&offset=#{offset}",
                                   nil, { "Authorization" => "Bearer #{tep_token}" })

      if response.success?
        data = JSON.parse(response.body).symbolize_keys

        # Transform response to match jean's expected format
        {
          transactions: data[:transactions] || [],
          pagination: data[:pagination] || {
            total: 0,
            limit: limit,
            offset: offset,
            has_more: false
          }
        }
      else
        Rails.logger.error "Wallet transactions API error: #{response.status} - #{response.body}"
        raise WalletError.new("Failed to get transactions from wallet service")
      end
    end
  end

  def self.resolve_user(user_id, tep_token: nil)
    @@circuit_breakers[:verification].call do
      Rails.logger.info "Resolving user: #{user_id.inspect}"

      # Call tween-pay TMCP user resolution endpoint
      begin
        response = make_wallet_request(:get, "/api/v1/tmcp/users/resolve/#{user_id}",
                                     nil, { "Authorization" => "Bearer #{tep_token}" })

        if response.success?
          data = response.symbolize_keys

          # Transform response to match jean's expected format
          {
            user_id: data[:user_id] || user_id,
            has_wallet: data[:has_wallet] || true,
            wallet_id: data[:wallet_id],
            verification_level: data[:verification_level] || 0,
            verification_name: data[:verification_name] || "None",
            can_invite: data[:can_invite] || false
          }
        end
      rescue WalletError => e
        if e.message.include?("HTTP 404")
          Rails.logger.info "User #{user_id} not found in wallet service (404), returning default response"
          # Return default response for non-existent users (allows wallet creation)
          {
            user_id: user_id,
            has_wallet: false,
            wallet_id: nil,
            verification_level: 0,
            verification_name: "None",
            can_invite: true
          }
        else
          # Re-raise other wallet service errors
          raise
        end
      end
    end
  end

  def self.initiate_p2p_transfer(recipient_user_id, amount, currency, tep_token, options = {})
    @@circuit_breakers[:transfers].call do
      request_body = {
        recipient: recipient_user_id,
        amount: amount,
        currency: currency,
        room_id: options[:room_id],
        note: options[:note],
        idempotency_key: options[:idempotency_key]
      }

      response = make_wallet_request(:post, "/api/v1/tmcp/transfers/p2p/initiate",
                                   request_body,
                                   { "Authorization" => "Bearer #{tep_token}" })

      response
    end
  end

  def self.confirm_p2p_transfer(transfer_id, auth_proof, tep_token)
    @@circuit_breakers[:transfers].call do
      request_body = {
        auth_proof: auth_proof
      }

      response = make_wallet_request(:post, "/api/v1/tmcp/transfers/p2p/#{transfer_id}/confirm",
                                   request_body,
                                   { "Authorization" => "Bearer #{tep_token}" })

      response
    end
  end

  def self.accept_p2p_transfer(transfer_id, tep_token)
    @@circuit_breakers[:transfers].call do
      response = make_wallet_request(:post, "/api/v1/tmcp/transfers/p2p/#{transfer_id}/accept",
                                   nil,
                                   { "Authorization" => "Bearer #{tep_token}" })

      response
    end
  end

  def self.reject_p2p_transfer(transfer_id, tep_token = nil, reason = nil)
    @@circuit_breakers[:transfers].call do
      headers = {}
      if tep_token
        headers["Authorization"] = "Bearer #{tep_token}"
      else
        internal_api_key = ENV.fetch("WALLET_INTERNAL_API_KEY", "")
        headers["X-Internal-API-Key"] = internal_api_key
      end

      body = {}
      body[:reason] = reason if reason

      response = make_wallet_request(:post, "/api/v1/tmcp/transfers/p2p/#{transfer_id}/reject",
                                   body,
                                   headers)

      response
    end
  end

  def self.get_transfer_info(transfer_id)
    @@circuit_breakers[:transfers].call do
      internal_api_key = ENV.fetch("WALLET_INTERNAL_API_KEY", "")

      response = make_wallet_request(:get, "/api/v1/internal/transfers/#{transfer_id}",
                                   nil,
                                   { "X-Internal-API-Key" => internal_api_key })

      response
    end
  end

  def self.create_payment_request(amount, currency, description, tep_token, options = {})
    @@circuit_breakers[:payments].call do
      request_body = {
        amount: amount,
        currency: currency,
        description: description,
        merchant_order_id: options[:merchant_order_id],
        callback_url: options[:callback_url],
        idempotency_key: options[:idempotency_key]
      }

      response = make_wallet_request(:post, "/api/v1/tmcp/payments/request",
                                   request_body,
                                   { "Authorization" => "Bearer #{tep_token}" })

      response
    end
  end

  def self.authorize_payment(payment_id, auth_proof, tep_token)
    @@circuit_breakers[:payments].call do
      request_body = {
        auth_proof: auth_proof
      }

      response = make_wallet_request(:post, "/api/v1/tmcp/payments/#{payment_id}/authorize",
                                   request_body,
                                   { "Authorization" => "Bearer #{tep_token}" })

      response
    end
  end

  # Legacy mock methods for backwards compatibility
  def self.get_verification_status(user_id)
    # Mock verification status (PROTO Section 6.4.2)
    {
      level: 2,
      level_name: "ID Verified",
      verified_at: "2024-01-15T10:00:00Z",
      limits: {
        daily_limit: 100000.00,
        transaction_limit: 50000.00,
        monthly_limit: 500000.00,
        currency: "USD"
      },
      features: {
        p2p_send: true,
        p2p_receive: true,
        miniapp_payments: true
      },
      can_upgrade: true,
      next_level: 3,
      upgrade_requirements: [ "address_proof", "enhanced_id" ]
    }
  end

  def self.request_mfa_challenge(payment_id, user_id)
    # Mock MFA challenge
    {
      challenge_id: "mfa_mock_#{SecureRandom.hex(8)}",
      methods: [
        {
          type: "transaction_pin",
          enabled: true,
          display_name: "Transaction PIN"
        },
        {
          type: "biometric",
          enabled: true,
          display_name: "Biometric Authentication",
          biometric_types: [ "fingerprint", "face_recognition" ]
        }
      ],
      required_method: "any",
      expires_at: (Time.current + 3.minutes).iso8601,
      max_attempts: 3
    }
  end

  def self.verify_mfa_response(challenge_id, method, credentials)
    # Mock MFA verification
    if credentials.is_a?(Hash) && credentials["pin"] == "1234"
      { status: "verified", proceed_to_processing: true }
    else
      { status: "failed", error: { code: "INVALID_CREDENTIALS", message: "Invalid credentials" } }
    end
  end

  def self.refund_payment(payment_id, amount, reason)
    # Mock payment refund
    {
      payment_id: payment_id,
      refund_id: "refund_mock_#{SecureRandom.hex(8)}",
      status: "completed",
      amount_refunded: amount
    }
  end

  def self.link_external_account(wallet_id, account_type, account_details)
    # Mock external account linking (PROTO Section 6.5.2)
    account_id = "ext_mock_#{SecureRandom.hex(8)}"
    {
      account_id: account_id,
      account_type: account_type,
      status: "pending_verification",
      masked_details: mask_account_details(account_type, account_details),
      created_at: Time.current.iso8601
    }
  end

  def self.verify_external_account(account_id, verification_data)
    # Mock account verification (PROTO Section 6.5.2)
    {
      account_id: account_id,
      status: "verified",
      verified_at: Time.current.iso8601,
      verification_method: "micro_deposit" # or "instant" or "manual"
    }
  end

  def self.fund_wallet(wallet_id, source_account_id, amount, currency)
    # Mock wallet funding (PROTO Section 6.5.2)
    funding_id = "fund_mock_#{SecureRandom.hex(8)}"
    {
      funding_id: funding_id,
      status: "processing",
      amount: amount,
      currency: currency,
      source_account_id: source_account_id,
      estimated_completion: (Time.current + 5.minutes).iso8601
    }
  end

  def self.initiate_withdrawal(wallet_id, destination_account_id, amount, currency)
    # Mock withdrawal initiation (PROTO Section 6.6.2)
    withdrawal_id = "wd_mock_#{SecureRandom.hex(8)}"
    {
      withdrawal_id: withdrawal_id,
      status: "pending",
      amount: amount,
      currency: currency,
      destination_account_id: destination_account_id,
      processing_fee: calculate_processing_fee(amount),
      estimated_completion: (Time.current + 1.day).iso8601
    }
  end

  private

  def self.mask_account_details(account_type, details)
    case account_type
    when "bank_account"
      "****#{details['account_number']&.last(4)}"
    when "debit_card", "credit_card"
      "****-****-****-#{details['card_number']&.last(4)}"
    else
      "****"
    end
  end

  def self.calculate_processing_fee(amount)
    # Simple fee calculation - in reality this would be more complex
    [ amount * 0.02, 2.99 ].max.round(2)
  end

  def self.circuit_breaker_metrics
    # Return circuit breaker status for monitoring (PROTO Section 7.7.4)
    @@circuit_breakers.transform_values(&:metrics)
  end
end
