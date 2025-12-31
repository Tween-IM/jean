class WalletService
  # TMCP Protocol Section 6: Mock Wallet Service Implementation
  # This is a temporary mock implementation for testing
  # TODO: Replace with real wallet service integration

  class WalletError < StandardError; end

  # Circuit breakers for different operations (PROTO Section 7.7)
  @@circuit_breakers = {
    balance: CircuitBreakerService.new("wallet_balance"),
    payments: CircuitBreakerService.new("wallet_payments"),
    transfers: CircuitBreakerService.new("wallet_transfers"),
    verification: CircuitBreakerService.new("wallet_verification")
  }

  def self.get_balance(user_id)
    @@circuit_breakers[:balance].call do
      # Mock balance response
      {
        wallet_id: "tw_mock_wallet_#{user_id.hash.abs}",
        user_id: user_id,
        balance: {
          available: 10000.00,
          pending: 0.00,
          currency: "USD"
        },
        limits: {
          daily_limit: 100000.00,
          daily_used: 0.00,
          transaction_limit: 50000.00
        },
        verification: {
          level: 2,
          level_name: "ID Verified",
          features: [ "standard_transactions", "weekly_limit" ],
          can_upgrade: false,
          next_level: nil,
          upgrade_requirements: []
        },
        status: "active"
      }
    end
  end

  def self.get_transactions(user_id, limit: 50, offset: 0)
    # Mock transaction history
    {
      transactions: [
        {
          txn_id: "txn_mock_123",
          type: "p2p_received",
          amount: 5000.00,
          currency: "USD",
          from: {
            user_id: "@mock_user:tween.example",
            display_name: "Mock User"
          },
          status: "completed",
          note: "Mock transaction",
          timestamp: "2025-12-18T12:00:00Z",
          room_id: "!mock_room:tween.example"
        }
      ],
      pagination: {
        total: 1,
        limit: limit,
        offset: offset,
        has_more: false
      }
    }
  end

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

  def self.resolve_user(user_id)
    if user_id.include?("nonexistent")
      { error: { code: "NO_WALLET", message: "User does not have a wallet", can_invite: true } }
    else
      {
        user_id: user_id,
        wallet_id: "tw_mock_wallet_#{user_id.hash.abs}",
        wallet_status: "active",
        display_name: "Mock User",
        avatar_url: "mxc://tween.example/mock_avatar",
        payment_enabled: true,
        created_at: "2024-01-15T10:00:00Z"
      }
    end
  end

  def self.initiate_p2p_transfer(sender_wallet, recipient_wallet, amount, currency, options = {})
    # Mock P2P transfer initiation
    transfer_id = "p2p_mock_#{SecureRandom.hex(8)}"
    {
      transfer_id: transfer_id,
      status: "completed", # Mock immediate completion
      amount: amount,
      sender: { user_id: options[:sender_user_id], wallet_id: sender_wallet },
      recipient: { user_id: options[:recipient_user_id], wallet_id: recipient_wallet },
      timestamp: Time.current.iso8601,
      room_id: options[:room_id]
    }
  end

  def self.accept_p2p_transfer(transfer_id, recipient_wallet)
    # Mock transfer acceptance
    {
      transfer_id: transfer_id,
      status: "completed",
      accepted_at: Time.current.iso8601,
      new_balance: 15000.00 # Mock new balance
    }
  end

  def self.reject_p2p_transfer(transfer_id)
    # Mock transfer rejection
    {
      transfer_id: transfer_id,
      status: "rejected",
      rejected_at: Time.current.iso8601
    }
  end

  def self.create_payment_request(user_wallet, miniapp_wallet, amount, currency, description, options = {})
    # Mock payment request creation
    payment_id = "pay_mock_#{SecureRandom.hex(8)}"
    {
      payment_id: payment_id,
      status: "pending_authorization",
      amount: amount,
      currency: currency,
      merchant: {
        miniapp_id: options[:miniapp_id] || "ma_mock",
        name: "Mock Mini-App",
        wallet_id: miniapp_wallet
      },
      authorization_required: true,
      expires_at: (Time.current + 5.minutes).iso8601,
      created_at: Time.current.iso8601
    }
  end

  def self.authorize_payment(payment_id, signature, device_info)
    # Mock payment authorization
    {
      payment_id: payment_id,
      status: "completed",
      txn_id: "txn_mock_#{SecureRandom.hex(8)}",
      completed_at: Time.current.iso8601
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
