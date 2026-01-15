require "test_helper"

class Api::V1::StoreControllerTest < ActionDispatch::IntegrationTest
  # TMCP Protocol Section 16.6: Mini-App Store Protocol

  setup do
    @user = User.create!(
      matrix_user_id: "@alice:tween.example",
      matrix_username: "alice",
      matrix_homeserver: "tween.example"
    )
    @token = TepTokenService.encode(
      { user_id: @user.matrix_user_id, miniapp_id: "ma_test" },
      scopes: [ "user:read" ]
    )
    @headers = { "Authorization" => "Bearer #{@token}" }
  end

  test "GET /api/v1/store/categories returns categories" do
    get api_v1_store_categories_path, headers: @headers

    assert_response :success
    response_data = JSON.parse(response.body)
    assert response_data["categories"].is_a?(Array)
    assert response_data["categories"].first["id"] == "shopping"
  end

  test "GET /api/v1/store/apps returns apps" do
    # Create test mini-app with valid app_id format
    # Use a unique app_id to avoid conflicts with other tests
    unique_suffix = SecureRandom.alphanumeric(6).downcase
    mini_app = MiniApp.create!(
      app_id: "ma_#{unique_suffix}",
      name: "Test App",
      version: "1.0.0",
      classification: :community,
      status: :active,
      manifest: {
        permissions: [ "storage_read", "user_read" ],
        scopes: [ "storage_read", "user_read" ],
        category: "shopping",
        rating: 4.5,
        rating_count: 100,
        icon_url: "https://example.com/icon.png",
        developer: { name: "Test Developer" }
      },
      install_count: 50
    )

    get api_v1_store_apps_path, headers: @headers

    assert_response :success
    response_data = JSON.parse(response.body)
    assert response_data["apps"].is_a?(Array)
    # Check that our created app is in the list
    app_ids = response_data["apps"].map { |app| app["miniapp_id"] }
    assert_includes app_ids, mini_app.app_id
  end

  teardown do
  end
end
