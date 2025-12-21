require "test_helper"

class Api::V1::StorageControllerTest < ActionDispatch::IntegrationTest
  # TMCP Protocol Section 10.3: Mini-App Storage tests

  setup do
    @user = User.create!(
      matrix_user_id: "@alice:tween.example",
      matrix_username: "alice",
      matrix_homeserver: "tween.example"
    )
    @miniapp_id = "ma_storage_app"
  end

  def auth_headers(scopes = [ "storage:read", "storage:write" ])
    token = TepTokenService.encode(
      { user_id: @user.matrix_user_id, miniapp_id: @miniapp_id },
      scopes: scopes
    )
    { "Authorization" => "Bearer #{token}" }
  end

  test "should list storage entries" do
    # Create some mock storage entries
    StorageEntry.create!(
      user: @user,
      miniapp_id: @miniapp_id,
      key: "test_key1",
      value: "test_value1"
    )
    StorageEntry.create!(
      user: @user,
      miniapp_id: @miniapp_id,
      key: "test_key2",
      value: "test_value2"
    )

    get "/api/v1/storage", headers: auth_headers

    assert_response :success

    response_body = JSON.parse(response.body)
    assert response_body.key?("entries")
    assert response_body["entries"].is_a?(Array)
    assert_equal 2, response_body["entries"].size
  end

  test "should create storage entry" do
    key = "new_key"
    value = "new_value"

    post "/api/v1/storage",
         params: { key: key, value: value },
         headers: auth_headers

    assert_response :created

    response_body = JSON.parse(response.body)
    assert_equal key, response_body["key"]
    assert_equal value, response_body["value"]
    assert response_body.key?("created_at")
    assert response_body.key?("updated_at")
  end

  test "should retrieve storage entry" do
    key = "test_key"
    value = "test_value"

    # Create entry
    StorageEntry.create!(
      user: @user,
      miniapp_id: @miniapp_id,
      key: key,
      value: value
    )

    get "/api/v1/storage/#{key}", headers: auth_headers

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal key, response_body["key"]
    assert_equal value, response_body["value"]
  end

  test "should update storage entry" do
    key = "update_key"
    original_value = "original_value"
    new_value = "updated_value"

    # Create entry
    StorageEntry.create!(
      user: @user,
      miniapp_id: @miniapp_id,
      key: key,
      value: original_value
    )

    put "/api/v1/storage/#{key}",
        params: { value: new_value },
        headers: auth_headers

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal key, response_body["key"]
    assert_equal new_value, response_body["value"]
    assert response_body["updated_at"] > response_body["created_at"]
  end

  test "should delete storage entry" do
    key = "delete_key"
    value = "delete_value"

    # Create entry
    StorageEntry.create!(
      user: @user,
      miniapp_id: @miniapp_id,
      key: key,
      value: value
    )

    delete "/api/v1/storage/#{key}", headers: auth_headers

    assert_response :no_content

    # Verify deletion
    get "/api/v1/storage/#{key}", headers: auth_headers
    assert_response :not_found
  end

  test "should handle batch storage operations" do
    # Section 10.3: Batch Operations
    batch_operations = {
      operations: [
        { type: "set", key: "batch_key1", value: "batch_value1" },
        { type: "set", key: "batch_key2", value: "batch_value2" },
        { type: "get", key: "batch_key1" }
      ]
    }

    post "/api/v1/storage/batch",
         params: batch_operations,
         headers: auth_headers

    assert_response :success

    response_body = JSON.parse(response.body)
    assert response_body.key?("results")
    assert_equal 3, response_body["results"].size
  end

  test "should return storage info" do
    # Create some entries
    StorageEntry.create!(
      user: @user,
      miniapp_id: @miniapp_id,
      key: "info_key1",
      value: "x" * 1000 # 1KB value
    )
    StorageEntry.create!(
      user: @user,
      miniapp_id: @miniapp_id,
      key: "info_key2",
      value: "y" * 2000 # 2KB value
    )

    get "/api/v1/storage/info", headers: auth_headers

    assert_response :success

    response_body = JSON.parse(response.body)
    assert response_body.key?("total_entries")
    assert response_body.key?("total_size_bytes")
    assert response_body.key?("limits")
    assert response_body["limits"].key?("max_entries")
    assert response_body["limits"].key?("max_total_size")
  end

  test "should enforce storage quotas" do
    # Create entries that approach the quota limit
    # Assuming 10MB total limit and 1MB per key limit
    large_value = "x" * (1024 * 1024) # 1MB

    post "/api/v1/storage",
         params: { key: "large_key", value: large_value },
         headers: auth_headers

    assert_response :created

    # Try to exceed per-key limit
    too_large_value = "x" * (1024 * 1024 + 1) # > 1MB

    post "/api/v1/storage",
         params: { key: "too_large_key", value: too_large_value },
         headers: auth_headers

    assert_response :bad_request
    assert_includes response.body, "exceeds maximum key size"
  end

  test "should require storage:read scope for reading" do
    key = "scope_test_key"

    # Create entry
    StorageEntry.create!(
      user: @user,
      miniapp_id: @miniapp_id,
      key: key,
      value: "test_value"
    )

    # Token without storage:read scope
    token_no_read = TepTokenService.encode(
      { user_id: @user.matrix_user_id, miniapp_id: @miniapp_id },
      scopes: [ "storage:write" ]
    )
    headers_no_read = { "Authorization" => "Bearer #{token_no_read}" }

    get "/api/v1/storage/#{key}", headers: headers_no_read

    assert_response :forbidden
    assert_includes response.body, "storage:read scope required"
  end

  test "should require storage:write scope for writing" do
    # Token without storage:write scope
    token_no_write = TepTokenService.encode(
      { user_id: @user.matrix_user_id, miniapp_id: @miniapp_id },
      scopes: [ "storage:read" ]
    )
    headers_no_write = { "Authorization" => "Bearer #{token_no_write}" }

    post "/api/v1/storage",
         params: { key: "write_test_key", value: "test_value" },
         headers: headers_no_write

    assert_response :forbidden
    assert_includes response.body, "storage:write scope required"
  end

  test "should isolate storage by user and miniapp" do
    # Create entry for different user/miniapp
    other_user = User.create!(
      matrix_user_id: "@bob:tween.example",
      matrix_username: "bob",
      matrix_homeserver: "tween.example"
    )

    StorageEntry.create!(
      user: other_user,
      miniapp_id: "ma_other_app",
      key: "isolated_key",
      value: "isolated_value"
    )

    # Our user should not see the other user's entry
    get "/api/v1/storage", headers: auth_headers

    response_body = JSON.parse(response.body)
    assert_empty response_body["entries"]
  end

  test "should handle TTL for storage entries" do
    key = "ttl_key"
    value = "ttl_value"
    ttl_seconds = 3600 # 1 hour

    post "/api/v1/storage",
         params: { key: key, value: value, ttl_seconds: ttl_seconds },
         headers: auth_headers

    assert_response :created

    # Entry should exist immediately
    get "/api/v1/storage/#{key}", headers: auth_headers
    assert_response :success

    # Mock TTL expiration by manually setting expiry
    entry = StorageEntry.find_by(user: @user, miniapp_id: @miniapp_id, key: key)
    entry.update(expires_at: 1.hour.ago)

    # Entry should be considered expired
    get "/api/v1/storage/#{key}", headers: auth_headers
    assert_response :not_found
  end
end
