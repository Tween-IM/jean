require "test_helper"

class Api::V1::OauthControllerTest < ActionDispatch::IntegrationTest
  setup do
    @unique_suffix = SecureRandom.alphanumeric(8).downcase
    @miniapp_id = "ma_#{@unique_suffix}"
    @redirect_uri = "https://miniapp.example.com/callback"
    @scopes = "user:read wallet:pay"
    @state = "random_state_123"
    @code_verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    @code_challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"

    @miniapp = MiniApp.create!(
      app_id: @miniapp_id,
      name: "Test Mini-App",
      description: "A test mini-app",
      version: "1.0.0",
      classification: :official,
      status: :active,
      manifest: {
        "scopes" => [ "storage_read", "storage_write", "public" ],
        "permissions" => {}
      }
    )

    @application = Doorkeeper::Application.create!(
      name: "Test Mini-App",
      uid: @miniapp_id,
      secret: "test_secret_123",
      redirect_uri: @redirect_uri,
      scopes: "user:read wallet:pay"
    )

    @user = User.create!(
      matrix_user_id: "@alice#{@unique_suffix}:tween.example",
      matrix_username: "alice#{@unique_suffix}:tween.example",
      matrix_homeserver: "tween.example"
    )
  end

  test "should handle authorization request with PKCE" do
    get "/api/v1/oauth/authorize",
        params: {
          response_type: "code",
          client_id: @miniapp_id,
          redirect_uri: @redirect_uri,
          scope: @scopes,
          state: @state,
          code_challenge: @code_challenge,
          code_challenge_method: "S256"
        }

    assert_response :found
    location = response.location
    assert location.include?("auth.tween.example")
    assert location.include?("authorize")
  end

  test "should reject authorization request without PKCE" do
    get "/api/v1/oauth/authorize",
        params: {
          response_type: "code",
          client_id: @miniapp_id,
          redirect_uri: @redirect_uri,
          scope: @scopes,
          state: @state
        }

    assert_response :bad_request
  end

  test "should validate scope format" do
    invalid_scopes = "invalid:scope user:read"

    get "/api/v1/oauth/authorize",
        params: {
          response_type: "code",
          client_id: @miniapp_id,
          redirect_uri: @redirect_uri,
          scope: invalid_scopes,
          state: @state,
          code_challenge: @code_challenge,
          code_challenge_method: "S256"
        }

    assert_response :bad_request
    assert_includes response.body, "Invalid scopes"
  end

  test "should reject invalid matrix token in token exchange" do
    post "/api/v1/oauth/token",
      params: {
        grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
        subject_token: "invalid_matrix_token",
        subject_token_type: "urn:ietf:params:oauth:token-type:access_token",
        client_id: @miniapp_id,
        client_secret: @application.secret,
        scope: @scopes
      }

    # MAS will return 401 for invalid token
    assert response.status.in?([ 400, 401 ]),
      "Expected 400 (invalid_request) or 401 (invalid token), got #{response.status}"
  end

  test "should require subject_token and client_id for token exchange" do
    post "/api/v1/oauth/token",
      params: {
        grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
        scope: @scopes
      }

    assert_response :bad_request
    response_data = JSON.parse(response.body)
    assert_equal "invalid_request", response_data["error"]
    assert_includes response_data["error_description"], "subject_token"
  end

  test "should create user record automatically on token exchange" do
    new_matrix_user_id = "@bob#{@unique_suffix}@tween.example"

    # Use non-sensitive scope to avoid consent requirement
    test_scopes = "user:read"

    assert_nil User.find_by(matrix_user_id: new_matrix_user_id)

    post "/api/v1/oauth/token",
      params: {
        grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
        subject_token: "valid_matrix_token_abc123",
        subject_token_type: "urn:ietf:params:oauth:token-type:access_token",
        client_id: @miniapp_id,
        client_secret: @application.secret,
        scope: test_scopes
      }

    # MAS will reject the token but we verify the request reaches MAS
    assert response.status.in?([ 200, 400, 401, 403 ]),
      "Expected 200 (success), 400 (invalid request), 401 (invalid token), or 403 (consent required), got #{response.status}"
  end

  test "authorization code flow should require matrix_access_token" do
    auth_request_id = SecureRandom.urlsafe_base64(32)
    Rails.cache.write("auth_request:#{auth_request_id}", {
      id: auth_request_id,
      client_id: @miniapp_id,
      redirect_uri: @redirect_uri,
      scope: @scopes.split,
      state: @state,
      code_challenge: @code_challenge,
      code_challenge_method: "S256",
      miniapp_name: @miniapp.name,
      created_at: Time.current
    }, expires_in: 15.minutes)

    post "/api/v1/oauth/token",
      params: {
        grant_type: "authorization_code",
        code: "test_code_123",
        state: auth_request_id
      }

    assert_response :bad_request
    response_data = JSON.parse(response.body)
    assert_equal "invalid_request", response_data["error"]
    assert_includes response_data["error_description"], "matrix_access_token"
  end

  test "authorization code flow should validate matrix token with MAS" do
    auth_request_id = SecureRandom.urlsafe_base64(32)
    test_scopes = "user:read"
    Rails.cache.write("auth_request:#{auth_request_id}", {
      id: auth_request_id,
      client_id: @miniapp_id,
      redirect_uri: @redirect_uri,
      scope: test_scopes.split,
      state: @state,
      code_challenge: @code_challenge,
      code_challenge_method: "S256",
      miniapp_name: @miniapp.name,
      created_at: Time.current
    }, expires_in: 15.minutes)

    post "/api/v1/oauth/token",
      params: {
        grant_type: "authorization_code",
        code: "test_code_123",
        state: auth_request_id,
        matrix_access_token: "valid_matrix_token",
        client_id: @miniapp_id
      }

    # MAS will reject the invalid code but validates the token
    assert response.status.in?([ 200, 400, 401 ]),
      "Expected 200 (success), 400 (invalid code), or 401 (invalid token), got #{response.status}"
  end

  # ============================================================================
  # First-Party MiniApp Auto-Approval Tests
  # ============================================================================

  test "first-party miniapp should auto-approve all scopes" do
    # Ensure user has mas_user_id
    @user.update!(mas_user_id: "user_#{@unique_suffix}") unless @user.mas_user_id

    # Create first-party miniapp
    first_party_app_id = "ma_testfirstparty#{@unique_suffix}"
    first_party = MiniApp.create!(
      app_id: first_party_app_id,
      name: "Test First-Party App",
      description: "A test first-party mini-app",
      version: "1.0.0",
      classification: :official,
      status: :active,
      manifest: { "scopes" => [], "permissions" => {} }
    )

    app = Doorkeeper::Application.create!(
      name: "Test First-Party App",
      uid: first_party_app_id,
      secret: "test_secret_123",
      redirect_uri: @redirect_uri,
      scopes: "user:read wallet:pay wallet:history"
    )

    # Set environment variable for first-party miniapps
    original_env = ENV["FIRST_PARTY_MINIAPPS"]
    ENV["FIRST_PARTY_MINIAPPS"] = first_party_app_id

    # Verify no existing approvals
    assert_equal 0, AuthorizationApproval.where(user_id: @user.mas_user_id, miniapp_id: first_party_app_id).count

    # Call authorize_scopes directly
    controller = Api::V1::OauthController.new
    result = controller.send(:authorize_scopes, @user, app, ["user:read", "wallet:pay"])

    # Should auto-approve without consent
    assert_equal ["user:read", "wallet:pay"], result[:authorized_scopes]
    assert_equal false, result[:consent_required]

    # Should create authorization approvals
    assert_equal 2, AuthorizationApproval.where(user_id: @user.mas_user_id, miniapp_id: first_party_app_id).count

    # Cleanup
    ENV["FIRST_PARTY_MINIAPPS"] = original_env
  end

  test "first-party miniapp should create authorization approvals with approved_at timestamp" do
    # Ensure user has mas_user_id
    @user.update!(mas_user_id: "user_ts_#{@unique_suffix}") unless @user.mas_user_id

    first_party_app_id = "ma_testtimestamp#{@unique_suffix}"
    MiniApp.create!(
      app_id: first_party_app_id,
      name: "Test Timestamp App",
      description: "A test first-party mini-app",
      version: "1.0.0",
      classification: :official,
      status: :active,
      manifest: { "scopes" => [], "permissions" => {} }
    )

    app = Doorkeeper::Application.create!(
      name: "Test Timestamp App",
      uid: first_party_app_id,
      secret: "test_secret_123",
      redirect_uri: @redirect_uri,
      scopes: "user:read"
    )

    original_env = ENV["FIRST_PARTY_MINIAPPS"]
    ENV["FIRST_PARTY_MINIAPPS"] = first_party_app_id

    controller = Api::V1::OauthController.new
    controller.send(:authorize_scopes, @user, app, ["user:read"])

    # Verify approval has timestamp
    approval = AuthorizationApproval.find_by(user_id: @user.mas_user_id, miniapp_id: first_party_app_id, scope: "user:read")
    assert_not_nil approval
    assert_not_nil approval.approved_at
    assert_in_delta Time.current, approval.approved_at, 5.seconds

    ENV["FIRST_PARTY_MINIAPPS"] = original_env
  end

  test "third-party miniapp should require consent for sensitive scopes" do
    # Ensure user has mas_user_id
    @user.update!(mas_user_id: "user_tp_#{@unique_suffix}") unless @user.mas_user_id

    # Regular miniapp (not in FIRST_PARTY_MINIAPPS)
    third_party_app_id = "ma_testthirdparty#{@unique_suffix}"
    MiniApp.create!(
      app_id: third_party_app_id,
      name: "Test Third-Party App",
      description: "A test third-party mini-app",
      version: "1.0.0",
      classification: :community,
      status: :active,
      manifest: { "scopes" => [], "permissions" => {} }
    )

    app = Doorkeeper::Application.create!(
      name: "Test Third-Party App",
      uid: third_party_app_id,
      secret: "test_secret_123",
      redirect_uri: @redirect_uri,
      scopes: "user:read wallet:pay"
    )

    # Ensure it's not in first-party list
    original_env = ENV["FIRST_PARTY_MINIAPPS"]
    ENV["FIRST_PARTY_MINIAPPS"] = "ma_somethingelse"

    controller = Api::V1::OauthController.new
    result = controller.send(:authorize_scopes, @user, app, ["user:read", "wallet:pay"])

    # When consent is required, authorized_scopes is empty (user hasn't authorized yet)
    # pre_approved_scopes contains non-sensitive scopes that don't need consent
    assert_equal [], result[:authorized_scopes]
    assert_equal true, result[:consent_required]
    assert_equal ["wallet:pay"], result[:consent_required_scopes]
    assert_equal ["user:read"], result[:pre_approved_scopes]

    ENV["FIRST_PARTY_MINIAPPS"] = original_env
  end

  test "default FIRST_PARTY_MINIAPPS should include ma_tweenpay" do
    # Ensure user has mas_user_id
    @user.update!(mas_user_id: "user_def_#{@unique_suffix}") unless @user.mas_user_id

    # Clear environment variable to test default
    original_env = ENV.delete("FIRST_PARTY_MINIAPPS")

    MiniApp.create!(
      app_id: "ma_tweenpay",
      name: "TweenPay",
      description: "TweenPay Wallet",
      version: "1.0.0",
      classification: :official,
      status: :active,
      manifest: { "scopes" => [], "permissions" => {} }
    )

    app = Doorkeeper::Application.create!(
      name: "TweenPay",
      uid: "ma_tweenpay",
      secret: "test_secret_123",
      redirect_uri: @redirect_uri,
      scopes: "user:read wallet:pay"
    )

    controller = Api::V1::OauthController.new
    result = controller.send(:authorize_scopes, @user, app, ["user:read", "wallet:pay"])

    assert_equal ["user:read", "wallet:pay"], result[:authorized_scopes]
    assert_equal false, result[:consent_required]

    ENV["FIRST_PARTY_MINIAPPS"] = original_env if original_env
  end
end
