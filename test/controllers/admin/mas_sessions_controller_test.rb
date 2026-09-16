# frozen_string_literal: true

require "test_helper"

# Tween ID sign-in for platform staff: OIDC authorization code + PKCE against
# the Matrix Authentication Service. jean never sees a password — MAS
# authenticates, and this only maps the returned subject onto a platform admin.
class Admin::MasSessionsControllerTest < ActionDispatch::IntegrationTest
  MAS_ISSUER = "http://mas.test"

  setup do
    @suffix = SecureRandom.hex(4)
    @admin = create_user("mas-admin-#{@suffix}")
    @admin.update!(platform_role: :super_admin, mas_user_id: "mas_#{@suffix}")
  end

  teardown do
    %w[MAS_AUTH_URL MAS_CLIENT_ID MAS_CLIENT_SECRET MAS_ADMIN_REDIRECT_URI MAS_CLIENT_SECRET_FILE].each { |key| ENV.delete(key) }
  end

  test "sign-in is offered only when MAS is configured" do
    %w[MAS_AUTH_URL MAS_CLIENT_ID MAS_CLIENT_SECRET].each { |key| ENV.delete(key) }

    get admin_mas_login_path

    assert_redirected_to admin_login_path
    follow_redirect!
    assert_match "not configured", response.body
  end

  test "the login page offers Tween ID when MAS is configured" do
    configure_mas!

    get admin_login_path

    assert_response :success
    assert_match "Continue with Tween ID", response.body
  end

  test "starting sign-in sends the browser to MAS with PKCE and a state" do
    configure_mas!

    get admin_mas_login_path

    assert_response :redirect
    target = URI.parse(response.location)
    query = Rack::Utils.parse_query(target.query)

    assert_equal "#{MAS_ISSUER}/authorize", "#{target.scheme}://#{target.host}#{target.path}"
    assert_equal "code", query["response_type"]
    assert_equal ENV["MAS_CLIENT_ID"], query["client_id"]
    assert_equal "openid", query["scope"]
    assert_equal "S256", query["code_challenge_method"]
    assert query["code_challenge"].present?
    assert_equal ENV["MAS_ADMIN_REDIRECT_URI"], query["redirect_uri"]
    assert_equal session[:admin_mas_state], query["state"]
  end

  test "a successful round trip signs the platform admin in" do
    configure_mas!
    stub_mas_round_trip(@admin.mas_user_id)

    start = start_sign_in
    get admin_mas_callback_path, params: { code: "auth-code", state: start }

    assert_redirected_to admin_dashboard_path
    follow_redirect!
    assert_match @admin.matrix_user_id, response.body
  end

  test "a tampered state is refused" do
    configure_mas!
    stub_mas_round_trip(@admin.mas_user_id)

    start = start_sign_in
    get admin_mas_callback_path, params: { code: "auth-code", state: "not-#{start}" }

    assert_redirected_to admin_login_path
    follow_redirect!
    assert_match "did not match", response.body
  end

  test "a code replayed without a live request is refused" do
    configure_mas!
    stub_mas_round_trip(@admin.mas_user_id)

    get admin_mas_callback_path, params: { code: "auth-code", state: "anything" }

    assert_redirected_to admin_login_path
    follow_redirect!
    assert_match "already been used or expired", response.body
  end

  test "a Tween ID with no platform account is refused" do
    configure_mas!
    stub_mas_round_trip("mas_someone_else")

    state = start_sign_in
    get admin_mas_callback_path, params: { code: "auth-code", state: state }

    assert_redirected_to admin_login_path
    follow_redirect!
    assert_match "No platform account is linked", response.body
  end

  test "a regular user is not a platform admin" do
    configure_mas!
    member = create_user("mas-member-#{@suffix}")
    member.update!(mas_user_id: "mas_member_#{@suffix}")
    stub_mas_round_trip(member.mas_user_id)

    state = start_sign_in
    get admin_mas_callback_path, params: { code: "auth-code", state: state }

    assert_redirected_to admin_login_path
    follow_redirect!
    assert_match "not a platform admin", response.body
  end

  test "an admin with MFA enabled is pushed to the second factor" do
    configure_mas!
    @admin.update!(admin_mfa_enabled: true, admin_mfa_secret: ROTP::Base32.random)
    stub_mas_round_trip(@admin.mas_user_id)

    state = start_sign_in
    get admin_mas_callback_path, params: { code: "auth-code", state: state }

    assert_redirected_to admin_mfa_path
    assert_equal @admin.id, session[:admin_mfa_pending_user_id]
    assert_nil session[:admin_user_id]
  end

  test "a cancelled consent screen comes back cleanly" do
    configure_mas!
    state = start_sign_in

    get admin_mas_callback_path, params: { error: "access_denied", state: state }

    assert_redirected_to admin_login_path
    follow_redirect!
    assert_match "cancelled", response.body
  end

  test "a MAS failure is reported without leaking internals" do
    configure_mas!
    stub_request(:post, "#{MAS_ISSUER}/oauth2/token")
      .to_return(status: 400, headers: { "Content-Type" => "application/json" },
        body: { error: "invalid_grant" }.to_json)

    state = start_sign_in
    get admin_mas_callback_path, params: { code: "expired", state: state }

    assert_redirected_to admin_login_path
    follow_redirect!
    assert_match "sign-in failed", response.body
  end

  test "the PKCE challenge is the S256 digest of the verifier" do
    verifier = "verifier-#{@suffix}"
    expected = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)

    assert_equal expected, Admin::MasOidc.code_challenge(verifier)
  end

  private

  def configure_mas!
    ENV["MAS_AUTH_URL"] = MAS_ISSUER
    ENV["MAS_CLIENT_ID"] = "01H9TESTCLIENT"
    ENV["MAS_CLIENT_SECRET"] = "secret-#{@suffix}"
    ENV["MAS_ADMIN_REDIRECT_URI"] = "http://www.example.com/admin/auth/mas/callback"
  end

  def start_sign_in
    get admin_mas_login_path
    session[:admin_mas_state]
  end

  def stub_mas_round_trip(mas_user_id)
    stub_request(:post, "#{MAS_ISSUER}/oauth2/token")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
        body: { access_token: "mas-access-token", token_type: "Bearer" }.to_json)

    stub_request(:get, "#{MAS_ISSUER}/oauth2/userinfo")
      .with(headers: { "Authorization" => "Bearer mas-access-token" })
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
        body: { sub: mas_user_id }.to_json)
  end

  def create_user(username)
    User.create!(
      matrix_user_id: "@#{username}:example.com",
      matrix_username: "#{username}:example.com",
      matrix_homeserver: "example.com"
    )
  end
end
