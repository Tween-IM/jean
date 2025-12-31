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
  end

  teardown do
    @miniapp.destroy if @miniapp&.persisted?
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
end
