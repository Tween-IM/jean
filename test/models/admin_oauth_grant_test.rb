require "test_helper"

class AdminOauthGrantTest < ActiveSupport::TestCase
  setup do
    ENV["MAS_AUTH_URL"] = "https://mas.test"
    ENV["MAS_CLIENT_ID"] = "admin-client"
    ENV["MAS_CLIENT_SECRET"] = "test-client-secret"
    @user = User.create!(matrix_user_id: "@grant_#{SecureRandom.hex(4)}:tween.im",
      matrix_username: "grant:tween.im", matrix_homeserver: "tween.im",
      platform_role: "super_admin", mas_user_id: SecureRandom.uuid)
    @key = SecureRandom.hex(32)
    @tokens = { "access_token" => "access-#{SecureRandom.hex(16)}", "refresh_token" => "refresh-#{SecureRandom.hex(16)}",
      "scope" => AdminOauthGrant::REQUIRED_SCOPES.join(" "), "expires_in" => 300, "token_type" => "Bearer" }
    @grant = AdminOauthGrant.install!(user: @user, key: @key, subject: @user.mas_user_id, tokens: @tokens)
  end

  teardown do
    %w[MAS_AUTH_URL MAS_CLIENT_ID MAS_CLIENT_SECRET].each { |key| ENV.delete(key) }
  end

  test "credentials are encrypted at rest and never exposed by inspection" do
    refute_includes @grant.encrypted_credentials, @tokens["access_token"]
    refute_includes @grant.encrypted_credentials, @tokens["refresh_token"]
    refute_includes @grant.inspect, @tokens["access_token"]
    assert_equal @tokens["access_token"], @grant.access_token_for(AdminOauthGrant::SYNAPSE_SCOPE)
    refute_equal @key, @grant.session_digest
  end

  test "one staff member cannot use another staff session or an unbound subject" do
    other = @user.dup
    other.matrix_user_id = "@other_#{SecureRandom.hex(4)}:tween.im"
    other.mas_user_id = SecureRandom.uuid
    other.save!
    assert_raises(AdminOauthGrant::ConnectionRequired) { AdminOauthGrant.for_session(other, @key) }
    assert_raises(AdminOauthGrant::ConnectionRequired) { AdminOauthGrant.for_session(@user, SecureRandom.hex(32)) }
    assert_raises(AdminOauthGrant::ConnectionRequired) do
      AdminOauthGrant.install!(user: @user, key: @key, subject: other.mas_user_id, tokens: @tokens)
    end
    assert_equal @tokens["access_token"], @grant.reload.credentials["access_token"]
  end

  test "scope denial cannot install a privileged grant" do
    assert_raises(AdminOauthGrant::ConnectionRequired) do
      AdminOauthGrant.install!(user: @user, key: @key, subject: @user.mas_user_id, tokens: @tokens.merge("scope" => "openid"))
    end
  end

  test "refresh rotates credentials and a stale second instance reuses the refreshed token" do
    @grant.update!(expires_at: 5.seconds.from_now)
    stale = AdminOauthGrant.find(@grant.id)
    stub_request(:post, "https://mas.test/oauth2/token").with(body: hash_including(
      "grant_type" => "refresh_token", "refresh_token" => @tokens["refresh_token"])).to_return(body: @tokens.merge(
      "access_token" => "new-access", "refresh_token" => "rotated-refresh").to_json)
    assert_equal "new-access", @grant.access_token_for(AdminOauthGrant::SYNAPSE_SCOPE)
    assert_equal "new-access", stale.access_token_for(AdminOauthGrant::SYNAPSE_SCOPE)
    assert_equal "rotated-refresh", @grant.reload.credentials["refresh_token"]
    assert_requested :post, "https://mas.test/oauth2/token", times: 1
  end

  test "invalid refresh grants are removed instead of falling back to a shared token" do
    @grant.update!(expires_at: 1.second.ago)
    stub_request(:post, "https://mas.test/oauth2/token").to_return(status: 400, body: { error: "invalid_grant" }.to_json)
    assert_raises(AdminOauthGrant::ConnectionRequired) { @grant.access_token_for(AdminOauthGrant::SYNAPSE_SCOPE) }
    refute AdminOauthGrant.exists?(@grant.id)
  end

  test "temporary provider failure preserves the grant but returns no expired token" do
    @grant.update!(expires_at: 1.second.ago)
    stub_request(:post, "https://mas.test/oauth2/token").to_timeout
    assert_raises(Admin::RemoteClient::Unavailable) { @grant.access_token_for(AdminOauthGrant::SYNAPSE_SCOPE) }
    assert AdminOauthGrant.exists?(@grant.id)
  end

  test "changed identity, role revocation and session expiry fail closed" do
    @user.update!(platform_role: "none")
    assert_raises(AdminOauthGrant::ConnectionRequired) { @grant.access_token_for(AdminOauthGrant::SYNAPSE_SCOPE) }
    refute AdminOauthGrant.exists?(@grant.id)
  end

  test "expired dashboard authorization requires connection again" do
    stub_request(:post, "https://mas.test/oauth2/revoke").to_return(body: "{}")
    @grant.update!(session_expires_at: 1.second.ago)
    assert_raises(AdminOauthGrant::ConnectionRequired) { AdminOauthGrant.for_session(@user, @key) }
    refute AdminOauthGrant.exists?(@grant.id)
  end

  test "logout removes the grant even when remote revocation fails" do
    stub_request(:post, "https://mas.test/oauth2/revoke").to_timeout
    AdminOauthGrant.disconnect(@key)
    refute AdminOauthGrant.exists?(@grant.id)
  end
end
