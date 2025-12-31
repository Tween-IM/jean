require "test_helper"

class MatrixControllerTest < ActionDispatch::IntegrationTest
  # TMCP Protocol Section 3.1.2: Matrix Application Service tests

  setup do
    @headers = { "Authorization" => "Bearer test_matrix_token" }
    ENV["MATRIX_HS_TOKEN"] = "test_matrix_token"

    # Create test user for user query tests
    User.find_or_create_by(matrix_user_id: "@test_user:tween.example") do |user|
      user.matrix_username = "test_user"
      user.matrix_homeserver = "tween.example"
      user.status = :active
    end
  end

  teardown do
    ENV.delete("MATRIX_HS_TOKEN")
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

    post "/_matrix/app/v1/transactions/txn123",
         params: { events: events },
         headers: @headers

    assert_response :success
    assert_equal "{}", response.body
  end

  test "should query existing user" do
    # Use find_or_create_by to avoid duplicate key error
    user = User.find_or_create_by(matrix_user_id: "@test_user:tween.example") do |u|
      u.matrix_username = "test_user"
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
    get "/_matrix/app/v1/ping",
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
    get "/_matrix/app/v1/ping"

    assert_response :unauthorized
    assert_equal "{\"error\":\"unauthorized\"}", response.body
  end

  test "should reject invalid AS token" do
    invalid_headers = { "Authorization" => "Bearer invalid_token" }

    get "/_matrix/app/v1/ping", headers: invalid_headers

    assert_response :unauthorized
    assert_equal "{\"error\":\"unauthorized\"}", response.body
  end
end
