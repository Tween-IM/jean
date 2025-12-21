require "test_helper"

class Api::V1::PaymentsControllerTest < ActionDispatch::IntegrationTest
  # TMCP Protocol Sections 7.3-7.4: Payment Processing with MFA tests

  setup do
    @user = User.create!(
      matrix_user_id: "@alice:tween.example",
      matrix_username: "alice",
      matrix_homeserver: "tween.example",
      wallet_id: "tw_test_wallet_123"
    )
    @token = TepTokenService.encode(
      { user_id: @user.matrix_user_id, miniapp_id: "ma_shop_001" },
      scopes: [ "wallet:pay" ],
      wallet_id: @user.wallet_id
    )
    @headers = { "Authorization" => "Bearer #{@token}" }
  end

  test "should create payment request" do
    # Section 7.3.1: Payment Request
    payment_params = {
      amount: 15000.00,
      currency: "USD",
      description: "Order #12345",
      merchant_order_id: "ORDER-2024-12345",
      callback_url: "https://miniapp.example.com/webhooks/payment",
      idempotency_key: SecureRandom.uuid
    }

    post "/api/v1/payments/request",
         params: payment_params,
         headers: @headers

    assert_response :created

    response_body = JSON.parse(response.body)
    assert response_body.key?("payment_id")
    assert response_body.key?("status")
    assert_equal "pending_authorization", response_body["status"]
    assert_equal 15000.00, response_body["amount"]
    assert_equal "USD", response_body["currency"]
    assert response_body.key?("merchant")
    assert response_body.key?("authorization_required")
  end

  test "should validate payment amount limits" do
    # Amount exceeds TMCP limit (50,000.00)
    payment_params = {
      amount: 75000.00,
      currency: "USD",
      description: "Large order",
      merchant_order_id: "ORDER-2024-LARGE",
      callback_url: "https://miniapp.example.com/webhooks/payment",
      idempotency_key: SecureRandom.uuid
    }

    post "/api/v1/payments/request",
         params: payment_params,
         headers: @headers

    assert_response :bad_request
    assert_includes response.body, "Amount must be between 0.01 and 50,000.00"
  end

  test "should require wallet:pay scope for payments" do
    token_no_pay = TepTokenService.encode(
      { user_id: @user.matrix_user_id, miniapp_id: "ma_shop_001" },
      scopes: [ "user:read" ]
    )
    headers_no_scope = { "Authorization" => "Bearer #{token_no_pay}" }

    payment_params = {
      amount: 1000.00,
      currency: "USD",
      description: "Test payment",
      merchant_order_id: "ORDER-2024-TEST",
      callback_url: "https://miniapp.example.com/webhooks/payment",
      idempotency_key: SecureRandom.uuid
    }

    post "/api/v1/payments/request",
         params: payment_params,
         headers: headers_no_scope

    assert_response :forbidden
    assert_includes response.body, "wallet:pay scope required"
  end

  test "should require MFA for high-value payments" do
    # Section 7.4: MFA for Payments
    # Amount > 50.00 should trigger MFA
    payment_params = {
      amount: 100.00,
      currency: "USD",
      description: "High-value order",
      merchant_order_id: "ORDER-2024-HIGH",
      callback_url: "https://miniapp.example.com/webhooks/payment",
      idempotency_key: SecureRandom.uuid
    }

    post "/api/v1/payments/request",
         params: payment_params,
         headers: @headers

    assert_response :created

    response_body = JSON.parse(response.body)
    assert response_body["mfa_required"]
  end

  test "should authorize payment with signature" do
    # Section 7.3.2: Payment Authorization
    payment_id = "pay_test123"

    # Mock payment data
    payment_data = {
      user_id: @user.matrix_user_id,
      amount: 1000.00,
      currency: "USD",
      description: "Test payment",
      merchant_order_id: "ORDER-2024-TEST",
      callback_url: "https://miniapp.example.com/webhooks/payment",
      mfa_required: false,
      status: "pending_authorization",
      created_at: Time.current
    }
    Rails.cache.write("payment:#{payment_id}", payment_data)

    post "/api/v1/payments/#{payment_id}/authorize",
         params: {
           signature: "mock_signature_base64",
           device_id: "device_test123",
           timestamp: Time.current.iso8601
         },
         headers: @headers

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal payment_id, response_body["payment_id"]
    assert_equal "completed", response_body["status"]
    assert response_body.key?("txn_id")
    assert_equal 1000.00, response_body["amount"]
  end

  test "should handle MFA challenge for payments" do
    # Section 7.4.2: MFA Challenge Request/Response
    payment_id = "pay_mfa_test123"

    # Mock MFA-required payment
    payment_data = {
      user_id: @user.matrix_user_id,
      amount: 100.00,
      currency: "USD",
      description: "MFA test payment",
      merchant_order_id: "ORDER-2024-MFA",
      callback_url: "https://miniapp.example.com/webhooks/payment",
      mfa_required: true,
      status: "pending_authorization",
      created_at: Time.current
    }
    Rails.cache.write("payment:#{payment_id}", payment_data)

    get "/api/v1/payments/#{payment_id}/mfa/challenge", headers: @headers

    assert_response :payment_required

    response_body = JSON.parse(response.body)
    assert_equal payment_id, response_body["payment_id"]
    assert_equal "mfa_required", response_body["status"]
    assert response_body.key?("mfa_challenge")
    assert response_body["mfa_challenge"].key?("challenge_id")
    assert response_body["mfa_challenge"].key?("methods")
  end

  test "should verify MFA credentials" do
    # Section 7.4.3: MFA Response Submission
    payment_id = "pay_mfa_verify123"
    challenge_id = "mfa_ch_test123"

    # Mock MFA challenge
    challenge_data = {
      challenge_id: challenge_id,
      payment_id: payment_id,
      methods: [ { type: "transaction_pin", enabled: true, display_name: "Transaction PIN" } ],
      required_method: "any",
      expires_at: (Time.current + 3.minutes).iso8601,
      max_attempts: 3
    }
    Rails.cache.write("mfa_challenge:#{challenge_id}", challenge_data)

    # Mock payment data
    payment_data = {
      user_id: @user.matrix_user_id,
      amount: 100.00,
      currency: "USD",
      description: "MFA verify payment",
      merchant_order_id: "ORDER-2024-MFA-VERIFY",
      callback_url: "https://miniapp.example.com/webhooks/payment",
      mfa_required: true,
      status: "pending_authorization",
      created_at: Time.current
    }
    Rails.cache.write("payment:#{payment_id}", payment_data)

    post "/api/v1/payments/#{payment_id}/mfa/verify",
         params: {
           challenge_id: challenge_id,
           method: "transaction_pin",
           credentials: { pin: "1234" },
           device_id: "device_test123",
           timestamp: Time.current.iso8601
         },
         headers: @headers

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal payment_id, response_body["payment_id"]
    assert_equal "verified", response_body["status"]
    assert response_body["proceed_to_processing"]
  end

  test "should handle MFA verification failure" do
    # Section 7.4.3: MFA Failure Response
    payment_id = "pay_mfa_fail123"
    challenge_id = "mfa_ch_fail123"

    # Mock MFA challenge
    challenge_data = {
      challenge_id: challenge_id,
      payment_id: payment_id,
      methods: [ { type: "transaction_pin", enabled: true, display_name: "Transaction PIN" } ],
      required_method: "any",
      expires_at: (Time.current + 3.minutes).iso8601,
      max_attempts: 3
    }
    Rails.cache.write("mfa_challenge:#{challenge_id}", challenge_data)

    post "/api/v1/payments/#{payment_id}/mfa/verify",
         params: {
           challenge_id: challenge_id,
           method: "transaction_pin",
           credentials: { pin: "wrong_pin" },
           device_id: "device_test123",
           timestamp: Time.current.iso8601
         },
         headers: @headers

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "failed", response_body["status"]
    assert response_body.key?("error")
    assert_equal "INVALID_CREDENTIALS", response_body["error"]["code"]
  end

  test "should handle payment refunds" do
    # Section 7.4: Refunds
    payment_id = "pay_refund123"

    post "/api/v1/payments/#{payment_id}/refund",
         params: {
           amount: 1000.00,
           reason: "customer_request",
           notes: "User requested refund"
         },
         headers: @headers

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal payment_id, response_body["payment_id"]
    assert response_body.key?("refund_id")
    assert_equal "completed", response_body["status"]
    assert_equal 1000.00, response_body["amount_refunded"]
  end

  test "should reject expired payment authorization" do
    payment_id = "pay_expired123"

    # Mock expired payment (created 10 minutes ago)
    expired_payment_data = {
      user_id: @user.matrix_user_id,
      amount: 1000.00,
      currency: "USD",
      description: "Expired payment",
      merchant_order_id: "ORDER-2024-EXPIRED",
      callback_url: "https://miniapp.example.com/webhooks/payment",
      mfa_required: false,
      status: "pending_authorization",
      created_at: 10.minutes.ago
    }
    Rails.cache.write("payment:#{payment_id}", expired_payment_data)

    post "/api/v1/payments/#{payment_id}/authorize",
         params: {
           signature: "mock_signature_base64",
           device_id: "device_test123",
           timestamp: Time.current.iso8601
         },
         headers: @headers

    assert_response :not_found
    assert_includes response.body, "Payment request not found or expired"
  end
end
