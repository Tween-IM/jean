require "test_helper"

class Admin::PerAdminAuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    ENV["MAS_AUTH_URL"] = "https://mas.test"
    ENV["MAS_CLIENT_ID"] = "admin-client"
    ENV["MAS_CLIENT_SECRET"] = "test-secret"
    ENV["MATRIX_API_URL"] = "https://synapse.test"
    @user = User.create!(matrix_user_id: "@oauth_#{SecureRandom.hex(4)}:tween.im",
      matrix_username: "oauth:tween.im", matrix_homeserver: "tween.im",
      mas_user_id: SecureRandom.uuid, platform_role: "super_admin")
    post admin_login_path, params: { matrix_user_id: @user.matrix_user_id, admin_token: ENV["ADMIN_ACCESS_TOKEN"] }
    @tokens = { access_token: "personal-access", refresh_token: "personal-refresh", token_type: "Bearer",
      scope: AdminOauthGrant::REQUIRED_SCOPES.join(" "), expires_in: 300 }
  end

  teardown do
    %w[MAS_AUTH_URL MAS_CLIENT_ID MAS_CLIENT_SECRET MATRIX_API_URL SYNAPSE_ADMIN_TOKEN].each { |key| ENV.delete(key) }
  end

  test "shared env credentials cannot authorize rooms" do
    ENV["SYNAPSE_ADMIN_TOKEN"] = "forbidden-shared-token"
    get admin_resource_path("rooms")
    assert_response :success
    assert_select "a", text: "Authorize with Tween ID"
    assert_not_requested :get, /synapse.test/
    get admin_users_path
    assert_response :success
  end

  test "personal authorization uses PKCE and stores tokens only encrypted on the server" do
    connect!
    assert_redirected_to admin_resource_path("rooms")
    grant = AdminOauthGrant.for_session(@user, session[:admin_oauth_key])
    assert_equal @user.mas_user_id, grant.subject
    refute_includes session.to_hash.to_json, "personal-access"
    refute_includes session.to_hash.to_json, "personal-refresh"
    stub_request(:get, "https://synapse.test/_synapse/admin/v1/rooms?from=0&limit=25")
      .with(headers: { "Authorization" => "Bearer personal-access" }).to_return(body: { rooms: [], total_rooms: 0 }.to_json)
    get admin_resource_path("rooms")
    assert_response :success
    assert_select "h2", text: "Connect your administration access", count: 0
  end

  test "another MAS identity cannot be attached to the current staff session" do
    stub_request(:post, "https://mas.test/oauth2/revoke").to_return(body: "{}")
    connect!(subject: SecureRandom.uuid)
    assert_redirected_to admin_dashboard_path
    assert_nil session[:admin_oauth_key]
    assert_equal 0, AdminOauthGrant.where(user: @user).count
    assert_requested :post, "https://mas.test/oauth2/revoke"
  end

  test "tampered state is refused without exchanging the code" do
    get admin_mas_connect_path
    get admin_mas_callback_path, params: { state: "wrong", code: "code" }
    assert_redirected_to admin_dashboard_path
    assert_not_requested :post, "https://mas.test/oauth2/token"
  end

  test "denied provider authorization leaves ordinary staff access intact" do
    get admin_mas_connect_path
    state = session[:admin_connection]["state"]
    get admin_mas_callback_path, params: { state: state, error: "access_denied" }
    assert_redirected_to admin_dashboard_path
    get admin_users_path
    assert_response :success
    assert_equal @user.id, session[:admin_user_id]
  end

  test "logout revokes and removes only this browser's authorization" do
    connect!
    stub_request(:post, "https://mas.test/oauth2/revoke").to_return(body: "{}")
    other_key = SecureRandom.hex(32)
    other = AdminOauthGrant.install!(user: @user, key: other_key, subject: @user.mas_user_id, tokens: @tokens.stringify_keys)
    delete admin_logout_path
    assert_nil session[:admin_oauth_key]
    assert_equal [other.id], AdminOauthGrant.where(user: @user).pluck(:id)
  end

  test "revoked upstream access forces reconnect and never uses environment token" do
    connect!
    stub_request(:get, "https://synapse.test/_synapse/admin/v1/rooms?from=0&limit=25")
      .to_return(status: 401, body: "{}")
    get admin_resource_path("rooms")
    assert_response :success
    assert_select "a", text: "Authorize with Tween ID"
    assert_equal 0, AdminOauthGrant.where(user: @user).count
  end

  private

  def connect!(subject: @user.mas_user_id)
    get admin_mas_connect_path
    query = Rack::Utils.parse_query(URI.parse(response.location).query)
    assert_includes query["scope"], "urn:synapse:admin:*"
    assert_includes query["scope"], "urn:mas:admin"
    assert_equal "S256", query["code_challenge_method"]
    stub_request(:post, "https://mas.test/oauth2/token").to_return(body: @tokens.to_json)
    stub_request(:get, "https://mas.test/oauth2/userinfo").to_return(body: { sub: subject }.to_json)
    get admin_mas_callback_path, params: { code: "code", state: query["state"] }
  end
end
