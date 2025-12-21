require "test_helper"

class Api::V1::OauthControllerTest < ActionDispatch::IntegrationTest
  # TMCP Protocol Section 4.2: OAuth 2.0 + PKCE Authorization Flow tests

  self.use_transactional_tests = false

  setup do
    @miniapp_id = "ma_shop_001"
    @redirect_uri = "https://miniapp.example.com/callback"
    @scopes = "user:read wallet:pay"
    @state = "random_state_123"
    @code_verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    @code_challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"

    # Create Doorkeeper application
    @application = Doorkeeper::Application.create!(
      name: "Test Mini-App",
      uid: @miniapp_id,
      secret: SecureRandom.hex(32),
      redirect_uri: @redirect_uri,
      scopes: "user:read wallet:pay"
    )
  end

  test "should handle authorization request with PKCE" do
    # Section 4.2.1: Authorization Code Flow with PKCE + Keycloak
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

    # Should redirect to Keycloak
    assert_response :found
    location = response.location
    assert location.include?("iam.tween.im") # Keycloak server
    assert location.include?("protocol/openid-connect/auth") # Keycloak auth endpoint
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

    # Should require PKCE challenge
    assert_response :bad_request
  end

  test "should handle token exchange with TMCP code" do
    # Skip this test for now - requires complex mocking of Keycloak integration
    skip "Keycloak integration test - requires external service mocking"
  end

  test "should handle token refresh" do
    # Skip complex refresh token test for now
    skip "Refresh token test - requires Keycloak integration mocking"
  end

  test "should validate scope format" do
    # Section 5.1: Scope validation
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

    # Should reject invalid scopes
    assert_response :bad_request
  end
end
