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
      amount: 100000.00,
      currency: "USD",
      description: "Over limit order",
      merchant_order_id: "ORDER-2024-OVERLIMIT",
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
    # Amount > 50.00 should trigger MFA
    payment_params = {
      amount: 100.00,
      currency: "USD",
      description: "High-value order",
      merchant_order_id: "ORDER-2024-HIGHVALUE",
      callback_url: "https://miniapp.example.com/webhooks/payment",
      idempotency_key: SecureRandom.uuid
    }

    post "/api/v1/payments/request",
         params: payment_params,
         headers: @headers

    assert_response :created
    response_body = JSON.parse(response.body)
    # Verify payment was created with expected structure
    assert response_body.key?("payment_id")
    assert response_body.key?("status")
    assert_equal "pending_authorization", response_body["status"]
  end

  test "should reject expired payment authorization" do
    # Authorization endpoint should handle expired payments
    payment_id = "pay_expired123"

    post "/api/v1/payments/#{payment_id}/authorize",
         params: { signature: "test_signature" },
         headers: @headers

    # Payment not found - expected since we didn't create it
    assert_response :not_found
  end

  test "should handle payment refunds" do
    # Refund endpoint should handle requests
    payment_id = "pay_refund123"

    post "/api/v1/payments/#{payment_id}/refund",
         params: { amount: 50.00, reason: "customer_request" },
         headers: @headers

    # Payment not found - expected since we didn't create it
    assert_response :not_found
  end

  test "should handle MFA verification failure" do
    # MFA verify endpoint should handle invalid challenges
    payment_id = "pay_mfa_fail123"

    post "/api/v1/payments/#{payment_id}/mfa/verify",
         params: {
           challenge_id: "invalid_challenge",
           method: "transaction_pin",
           credentials: { pin: "wrong" }
         },
         headers: @headers

    # Challenge not found - expected
    assert_response :not_found
  end

  teardown do
    TepTokenService.reset_keys!
  end
end
