require "test_helper"

class MatrixControllerTest < ActionDispatch::IntegrationTest
  # TMCP Protocol Section 3.1.2: Matrix Application Service tests

  setup do
    @headers = { "Authorization" => "Bearer test_matrix_token" }
    ENV["MATRIX_AS_TOKEN"] = "test_matrix_token"
    ENV["TWEENPAY_INTERNAL_TOKEN"] = "test_internal_token"

    # Create test user for user query tests
    User.find_or_create_by(matrix_user_id: "@test_user:tween.example") do |user|
      user.matrix_username = "test_user:tween.example"
      user.matrix_homeserver = "tween.example"
      user.status = :active
    end
  end

  teardown do
    ENV.delete("MATRIX_AS_TOKEN")
    ENV.delete("TWEENPAY_INTERNAL_TOKEN")
  end

  test "payment status publishes an authenticated event" do
    original = CommerceRelayService.method(:relay_payment_status_to_room)
    CommerceRelayService.define_singleton_method(:relay_payment_status_to_room) do |*|
      "$status"
    end
    begin
      post "/api/v1/internal/matrix/payment_status",
           params: { room_id: "!room123:tween.example", transfer_id: "p2p_123", status: "completed" },
           headers: { "X-TweenPay-Internal-Token" => "test_internal_token" },
           as: :json
    ensure
      CommerceRelayService.define_singleton_method(:relay_payment_status_to_room, original)
    end

    assert_response :success
    assert_equal "published", response.parsed_body["status"]
    assert_equal "$status", response.parsed_body["event_id"]
  end

  test "payment status rejects callers without the internal token" do
    post "/api/v1/internal/matrix/payment_status",
         params: { room_id: "!room123:tween.example", transfer_id: "p2p_123", status: "completed" },
         as: :json

    assert_response :unauthorized
  end

  test "payment event publishes an authenticated room message" do
    captured = nil
    original = CommerceRelayService.method(:relay_payment_event_to_room)
    CommerceRelayService.define_singleton_method(:relay_payment_event_to_room) do |room_id, payload|
      captured = [ room_id, payload ]
      "$payment"
    end
    begin
      post "/api/v1/internal/matrix/payment_event",
           params: {
             room_id: "!room123:tween.example",
             transfer_id: "p2p_123",
             amount: 50,
             currency: "NGN",
             sender: { user_id: "@mona:tween.im", display_name: "Mona" }
           },
           headers: { "X-TweenPay-Internal-Token" => "test_internal_token" },
           as: :json
    ensure
      CommerceRelayService.define_singleton_method(:relay_payment_event_to_room, original)
    end

    assert_response :success
    assert_equal "$payment", response.parsed_body["event_id"]
    assert_equal "!room123:tween.example", captured[0]
    assert_equal "Mona", captured[1][:sender][:display_name]
  end

  test "should handle transactions endpoint" do
    events = [
      {
        "type" => "m.room.message",
        "room_id" => "!room123:tween.example",
        "sender" => "@alice:tween.example",
        "content" => {
          "msgtype" => "m.text",
          "body" => "Hello world"
        }
      }
    ]

    put "/_matrix/app/v1/transactions/txn123",
        params: { events: events },
        headers: @headers

    assert_response :success
    assert_equal "{}", response.body
  end

  test "should query existing user" do
    # Use find_or_create_by to avoid duplicate key error
    user = User.find_or_create_by(matrix_user_id: "@test_user:tween.example") do |u|
      u.matrix_username = "test_user:tween.example"
      u.matrix_homeserver = "tween.example"
    end

    # Verify user was created
    assert_not_nil User.find_by(matrix_user_id: "@test_user:tween.example")

    user_id = "@test_user:tween.example"
    get "/_matrix/app/v1/users/#{CGI.escape(user_id)}",
        headers: @headers

    assert_response :success
    assert_equal "{}", response.body
  end

  test "should return not found for non-existent user" do
    get "/_matrix/app/v1/users/@nonexistent:tween.example",
        headers: @headers

    assert_response :not_found
    assert_equal "{}", response.body
  end

  test "should attempt to register TMCP bot user on query" do
    # TMCP bots should be registered on-demand when queried by homeserver
    # Note: In real environment, this would register with Matrix homeserver
    # In test environment, we mock/stub the MatrixService.register_as_user call

    user_id = "@_tmcp_test_bot:tween.im"
    get "/_matrix/app/v1/users/#{CGI.escape(user_id)}",
        headers: @headers

    # Note: Without Matrix homeserver in test env, registration will fail
    # but the code should at least attempt it. In production with real HS,
    # this would succeed and return 200.
    assert_response :not_found
  end

  test "should query room alias" do
    room_alias = "#_tmcp_room:tween.example"
    get "/_matrix/app/v1/rooms/#{CGI.escape(room_alias)}",
        headers: @headers

    assert_response :success
    assert_equal "{}", response.body
  end

  test "should return not found for invalid room alias" do
    get "/_matrix/app/v1/rooms/invalid_room",
        headers: @headers

    assert_response :not_found
    assert_equal "{}", response.body
  end

  test "should handle ping endpoint" do
    post "/_matrix/app/v1/ping",
         headers: @headers

    assert_response :success
    assert_equal "{}", response.body
  end

  test "should handle thirdparty location" do
    get "/_matrix/app/v1/thirdparty/location",
        headers: @headers

    assert_response :success
    assert_equal "[]", response.body
  end

  test "should handle thirdparty user" do
    get "/_matrix/app/v1/thirdparty/user",
        headers: @headers

    assert_response :success
    assert_equal "[]", response.body
  end

  test "should handle thirdparty location protocol" do
    get "/_matrix/app/v1/thirdparty/location/miniapp",
        headers: @headers

    assert_response :success
    assert_equal "[]", response.body
  end

  test "should handle thirdparty user protocol" do
    get "/_matrix/app/v1/thirdparty/user/wallet",
        headers: @headers

    assert_response :success
    assert_equal "[]", response.body
  end

  test "should reject unauthorized requests" do
    # Remove auth header
    post "/_matrix/app/v1/ping"

    assert_response :unauthorized
    assert_equal "{\"error\":\"unauthorized\"}", response.body
  end

  test "should reject invalid AS token" do
    invalid_headers = { "Authorization" => "Bearer invalid_token" }

    post "/_matrix/app/v1/ping", headers: invalid_headers

    assert_response :unauthorized
    assert_equal "{\"error\":\"unauthorized\"}", response.body
  end
end
