require "test_helper"

class Api::V1::OauthControllerTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

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
      classification: :community,
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
      matrix_user_id: "@alice#{@unique_suffix}@tween.example",
      matrix_username: "alice#{@unique_suffix}",
      matrix_homeserver: "tween.example"
    )
  end

  teardown do
    @miniapp.destroy if @miniapp&.persisted?
    @application.destroy if @application&.persisted?
    @user.destroy if @user&.persisted?
    Rails.cache.clear
    TepTokenService.reset_keys!
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

  test "should exchange matrix access token for TEP token" do
    stub_request(:post, "https://auth.tween.example/oauth2/introspect")
      .with(body: hash_including("token" => "valid_matrix_token_abc123"))
      .to_return(
        status: 200,
        body: {
          active: true,
          sub: @user.matrix_user_id,
          display_name: "Alice",
          avatar_url: "mxc://tween.example/avatar123",
          device_id: "GHTYAJCE",
          sid: "mas_session_abc"
        }.to_json
      )

    stub_request(:post, "https://auth.tween.example/oauth2/token")
      .to_return(
        status: 200,
        body: {
          access_token: "new_matrix_token_xyz789",
          token_type: "Bearer",
          expires_in: 300
        }.to_json
      )

    post "/api/v1/oauth/token",
      params: {
        grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
        subject_token: "valid_matrix_token_abc123",
        subject_token_type: "urn:ietf:params:oauth:token-type:access_token",
        client_id: @miniapp_id,
        client_secret: @application.secret,
        scope: @scopes
      }

    assert_response :ok

    response_data = JSON.parse(response.body)
    assert response_data["access_token"].start_with?("tep.")
    assert_equal "Bearer", response_data["token_type"]
    assert_equal @user.matrix_user_id, response_data["user_id"]
    assert_not_nil response_data["wallet_id"]
    assert_equal 86400, response_data["expires_in"]
    assert_not_nil response_data["refresh_token"]
    assert response_data["matrix_access_token"].present?
    assert response_data["delegated_session"] == true
  end

  test "should reject invalid matrix token in token exchange" do
    stub_request(:post, "https://mas.tween.example/oauth2/introspect")
      .with(body: hash_including("token" => "invalid_matrix_token"))
      .to_return(status: 200, body: { active: false }.to_json)

    post "/api/v1/oauth/token",
      params: {
        grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
        subject_token: "invalid_matrix_token",
        subject_token_type: "urn:ietf:params:oauth:token-type:access_token",
        client_id: @miniapp_id,
        client_secret: @application.secret,
        scope: @scopes
      }

    assert_response :bad_request
    response_data = JSON.parse(response.body)
    assert_equal "invalid_grant", response_data["error"]
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

  test "should create user record automatically on token exchange" do
    new_matrix_user_id = "@bob#{@unique_suffix}@tween.example"

    stub_request(:post, "https://mas.tween.example/oauth2/introspect")
      .with(body: hash_including("token" => "valid_matrix_token_abc123"))
      .to_return(status: 200, body: {
        active: true,
        sub: new_matrix_user_id,
        display_name: "Bob",
        avatar_url: "mxc://tween.example/avatar456",
        device_id: "DEVICE123",
        sid: "mas_session_xyz"
      }.to_json)

    stub_request(:post, "https://mas.tween.example/oauth2/token")
      .to_return(status: 200, body: {
        access_token: "new_matrix_token_xyz789",
        token_type: "Bearer",
        expires_in: 300
      }.to_json)

    assert_nil User.find_by(matrix_user_id: new_matrix_user_id)

    post "/api/v1/oauth/token",
      params: {
        grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
        subject_token: "valid_matrix_token_abc123",
        subject_token_type: "urn:ietf:params:oauth:token-type:access_token",
        client_id: @miniapp_id,
        client_secret: @application.secret,
        scope: @scopes
      }

    assert_response :ok

    user = User.find_by(matrix_user_id: new_matrix_user_id)
    assert_not_nil user, "User should have been created for #{new_matrix_user_id}"
    assert_equal "bob#{@unique_suffix}", user.matrix_username
    assert_equal "tween.example", user.matrix_homeserver
  end

  test "should create user record automatically on token exchange" do
    new_matrix_user_id = "@bob#{@unique_suffix}@tween.example"

    stub_request(:post, "https://auth.tween.example/oauth2/introspect")
      .with(body: hash_including("token" => "valid_matrix_token_abc123"))
      .to_return(
        status: 200,
        body: {
          active: true,
          sub: new_matrix_user_id,
          display_name: "Bob",
          avatar_url: "mxc://tween.example/avatar456",
          device_id: "DEVICE123",
          sid: "mas_session_xyz"
        }.to_json
      )

    stub_request(:post, "https://auth.tween.example/oauth2/token")
      .to_return(
        status: 200,
        body: {
          access_token: "new_matrix_token_xyz789",
          token_type: "Bearer",
          expires_in: 300
        }.to_json
      )

    assert_nil User.find_by(matrix_user_id: new_matrix_user_id)

    post "/api/v1/oauth/token",
      params: {
        grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
        subject_token: "valid_matrix_token_abc123",
        subject_token_type: "urn:ietf:params:oauth:token-type:access_token",
        client_id: @miniapp_id,
        client_secret: @application.secret,
        scope: @scopes
      }

    assert_response :ok

    user = User.find_by(matrix_user_id: new_matrix_user_id)
    assert_not_nil user, "User should have been created for #{new_matrix_user_id}"
    assert_equal "bob#{@unique_suffix}", user.matrix_username
    assert_equal "tween.example", user.matrix_homeserver
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

    stub_request(:post, "https://mas.tween.example/oauth2/introspect")
      .with(body: hash_including("token" => "valid_matrix_token"))
      .to_return(
        status: 200,
        body: {
          active: true,
          sub: @user.matrix_user_id,
          display_name: "Alice",
          avatar_url: "mxc://tween.example/avatar123",
          device_id: "DEVICE123",
          sid: "mas_session_abc"
        }.to_json
      )

    stub_request(:post, "https://mas.tween.example/oauth2/token")
      .to_return(status: 200, body: {
        access_token: "new_matrix_token_xyz789",
        token_type: "Bearer",
        expires_in: 300
      }.to_json)

    post "/api/v1/oauth/token",
      params: {
        grant_type: "authorization_code",
        code: "test_code_123",
        state: auth_request_id,
        matrix_access_token: "valid_matrix_token",
        client_id: @miniapp_id
      }

    assert_response :ok
    response_data = JSON.parse(response.body)
    assert_equal @user.matrix_user_id, response_data["user_id"]
    assert_not_nil response_data["wallet_id"]
    assert response_data["matrix_access_token"].present?
  end
end
end
