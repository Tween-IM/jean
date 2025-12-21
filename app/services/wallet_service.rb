class WalletService
  # TMCP Protocol Section 6: Mock Wallet Service Implementation
  # This is a temporary mock implementation for testing
  # TODO: Replace with real wallet service integration

  class WalletError < StandardError; end

  def self.get_balance(user_id)
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

  def self.resolve_user(user_id)
    if user_id.include?("nonexistent")
      { error: { code: "NO_WALLET", message: "User does not have a wallet" } }
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
end
