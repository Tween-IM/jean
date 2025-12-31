require "test_helper"

class Api::V1::GiftsControllerTest < ActionDispatch::IntegrationTest
  # TMCP Protocol Section 7.5: Group Gift Distribution tests

  setup do
    @user = User.create!(
      matrix_user_id: "@alice:tween.example",
      matrix_username: "alice",
      matrix_homeserver: "tween.example"
    )
    @token = TepTokenService.encode(
      { user_id: @user.matrix_user_id, miniapp_id: "ma_gift_app" },
      scopes: [ "wallet:pay" ]
    )
    @headers = { "Authorization" => "Bearer #{@token}" }
  end

  test "should create individual gift" do
    # Section 7.5.2: Create Group Gift (Individual)
    gift_params = {
      type: "individual",
      recipient: "@bob:tween.example",
      amount: 5000.00,
      currency: "USD",
      message: "Happy Birthday! 🎉",
      room_id: "!chat123:tween.example",
      idempotency_key: SecureRandom.uuid
    }

    post "/api/v1/gifts/create",
         params: gift_params,
         headers: @headers

    assert_response :created

    response_body = JSON.parse(response.body)
    assert response_body.key?("gift_id")
    assert_equal "individual", response_body["type"]
    assert_equal "active", response_body["status"]
    assert_equal 5000.00, response_body["total_amount"]
    assert_equal 1, response_body["count"]
    assert response_body.key?("creator")
    assert response_body.key?("expires_at")
  end

  test "should create group gift" do
    # Section 7.5.2: Create Group Gift
    gift_params = {
      type: "group",
      room_id: "!groupchat:tween.example",
      total_amount: 10000.00,
      currency: "USD",
      count: 5,
      distribution: "random",
      message: "Happy Friday! 🎁",
      expires_in_seconds: 86400,
      idempotency_key: SecureRandom.uuid
    }

    post "/api/v1/gifts/create",
         params: gift_params,
         headers: @headers

    assert_response :created

    response_body = JSON.parse(response.body)
    assert response_body.key?("gift_id")
    assert_equal "group", response_body["type"]
    assert_equal "active", response_body["status"]
    assert_equal 10000.00, response_body["total_amount"]
    assert_equal 5, response_body["count"]
    assert_equal 5, response_body["remaining"]
    assert response_body.key?("creator")
    assert response_body.key?("expires_at")
  end

  test "should validate gift parameters" do
    # Invalid count (too high)
    gift_params = {
      type: "group",
      room_id: "!groupchat:tween.example",
      total_amount: 10000.00,
      currency: "USD",
      count: 150, # Exceeds max 100
      distribution: "random",
      message: "Too many recipients",
      idempotency_key: SecureRandom.uuid
    }

    post "/api/v1/gifts/create",
         params: gift_params,
         headers: @headers

    assert_response :bad_request
    assert_includes response.body, "Gift count must be between 2 and 100"
  end

  test "should validate distribution algorithm" do
    # Invalid distribution
    gift_params = {
      type: "group",
      room_id: "!groupchat:tween.example",
      total_amount: 10000.00,
      currency: "USD",
      count: 5,
      distribution: "invalid_algorithm",
      message: "Invalid distribution",
      idempotency_key: SecureRandom.uuid
    }

    post "/api/v1/gifts/create",
         params: gift_params,
         headers: @headers

    assert_response :bad_request
    response_body = JSON.parse(response.body)
    assert_equal "Distribution must be \"random\" or \"equal\"", response_body["message"]
  end

  test "should validate amount limits" do
    # Amount exceeds TMCP limit
    gift_params = {
      type: "group",
      room_id: "!groupchat:tween.example",
      total_amount: 75000.00, # Exceeds 50,000.00
      currency: "USD",
      count: 5,
      distribution: "equal",
      message: "Too expensive",
      idempotency_key: SecureRandom.uuid
    }

    post "/api/v1/gifts/create",
         params: gift_params,
         headers: @headers

    assert_response :bad_request
    assert_includes response.body, "Total amount must be between 0.01 and 50,000.00"
  end

  test "should open gift and receive amount" do
    # Section 7.5.3: Open Group Gift
    gift_id = "gift_test123"

    # Mock gift data
    gift_data = {
      gift_id: gift_id,
      type: "group",
      status: "active",
      total_amount: 10000.00,
      currency: "USD",
      count: 5,
      remaining: 5,
      distribution: "random",
      message: "Test gift",
      creator: {
        user_id: "@alice:tween.example",
        wallet_id: "tw_user_alice"
      },
      room_id: "!groupchat:tween.example",
      expires_at: (Time.current + 1.day).iso8601,
      opened_by: []
    }
    Rails.cache.write("gift:#{gift_id}", gift_data)

    post "/api/v1/gifts/#{gift_id}/open",
         params: { device_id: "device_test" },
         headers: @headers

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal gift_id, response_body["gift_id"]
    assert response_body.key?("amount_received")
    assert response_body["amount_received"].is_a?(Numeric)
    assert response_body.key?("message")
    assert response_body.key?("sender")
    assert response_body.key?("opened_at")
    assert response_body.key?("stats")
  end

  test "should prevent opening already opened gift" do
    # Section 7.5.3: Prevent duplicate opening
    gift_id = "gift_already_opened123"

    # Mock gift data with user already opened
    gift_data = {
      gift_id: gift_id,
      type: "group",
      status: "active",
      total_amount: 10000.00,
      currency: "USD",
      count: 5,
      remaining: 4,
      distribution: "equal",
      message: "Already opened by user",
      creator: {
        user_id: "@alice:tween.example",
        wallet_id: "tw_user_alice"
      },
      room_id: "!groupchat:tween.example",
      expires_at: (Time.current + 1.day).iso8601,
      opened_by: [ {
        user_id: @user.matrix_user_id,
        amount: 2000.00,
        opened_at: Time.current.iso8601
      } ]
    }
    Rails.cache.write("gift:#{gift_id}", gift_data)

    post "/api/v1/gifts/#{gift_id}/open",
         params: { device_id: "device_test" },
         headers: @headers

    assert_response :conflict
    assert_includes response.body, "You have already opened this gift"
  end

  test "should handle gift not found" do
    nonexistent_gift_id = "gift_nonexistent123"

    post "/api/v1/gifts/#{nonexistent_gift_id}/open",
         params: { device_id: "device_test" },
         headers: @headers

    assert_response :not_found
    assert_includes response.body, "Gift not found or expired"
  end

  test "should handle empty gift" do
    # Section 7.5.3: Gift fully claimed
    gift_id = "gift_empty123"

    # Mock empty gift
    gift_data = {
      gift_id: gift_id,
      type: "group",
      status: "fully_opened",
      total_amount: 10000.00,
      currency: "USD",
      count: 5,
      remaining: 0,
      distribution: "equal",
      message: "All claimed",
      creator: {
        user_id: "@alice:tween.example",
        wallet_id: "tw_user_alice"
      },
      room_id: "!groupchat:tween.example",
      expires_at: (Time.current + 1.day).iso8601,
      opened_by: []
    }
    Rails.cache.write("gift:#{gift_id}", gift_data)

    post "/api/v1/gifts/#{gift_id}/open",
         params: { device_id: "device_test" },
         headers: @headers

    assert_response :gone
    assert_includes response.body, "All gifts have been claimed"
  end

  test "should handle idempotency for gift creation" do
    # Section 7.5.2: Idempotency
    idempotency_key = SecureRandom.uuid

    gift_params = {
      type: "group",
      room_id: "!groupchat:tween.example",
      total_amount: 5000.00,
      currency: "USD",
      count: 3,
      distribution: "equal",
      message: "Idempotency test",
      idempotency_key: idempotency_key
    }

    # First request
    post "/api/v1/gifts/create",
         params: gift_params,
         headers: @headers

    assert_response :created

    # Duplicate request
    post "/api/v1/gifts/create",
         params: gift_params,
         headers: @headers

    assert_response :conflict
    assert_includes response.body, "Duplicate request with same idempotency key"
  end

  test "should require wallet:pay scope for gifts" do
    token_no_pay = TepTokenService.encode(
      { user_id: @user.matrix_user_id, miniapp_id: "ma_gift_app" },
      scopes: [ "user:read" ]
    )
    headers_no_scope = { "Authorization" => "Bearer #{token_no_pay}" }

    gift_params = {
      type: "individual",
      recipient: "@bob:tween.example",
      amount: 1000.00,
      currency: "USD",
      message: "Test gift",
      room_id: "!chat123:tween.example",
      idempotency_key: SecureRandom.uuid
    }

    post "/api/v1/gifts/create",
         params: gift_params,
         headers: headers_no_scope

    assert_response :forbidden
    assert_includes response.body, "wallet:pay scope required"
  end

  teardown do
    Rails.cache.clear
    TepTokenService.reset_keys!
  end
end
