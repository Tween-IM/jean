require "test_helper"

class MasClientServiceTest < ActiveSupport::TestCase
  setup do
    @mas_client = MasClientService.new(
      client_id: "test_client",
      client_secret: "test_secret",
      token_url: "https://auth.tween.im/oauth2/token",
      introspection_url: "https://auth.tween.im/oauth2/introspect",
      revocation_url: "https://auth.tween.im/oauth2/revoke"
    )
  end

  test "#client_credentials_grant returns token data" do
    mock_response = {
      "access_token" => "test_access_token_123",
      "token_type" => "Bearer",
      "expires_in" => 300,
      "scope" => "openid urn:matrix:org.matrix.msc2967.client:api:*"
    }

    stub_request(:post, "https://auth.tween.im/oauth2/token")
      .to_return(status: 200, body: mock_response.to_json)

    result = @mas_client.client_credentials_grant

    assert_equal "test_access_token_123", result[:access_token]
    assert_equal "Bearer", result[:token_type]
    assert_equal 300, result[:expires_in]
    assert result[:expires_at].present?
  end

  test "#exchange_matrix_token_for_tep returns TEP token with correct claims" do
    mas_user_info = {
      "active" => true,
      "sub" => "@alice:tween.im",
      "display_name" => "Alice",
      "avatar_url" => "mxc://tween.im/avatar123",
      "device_id" => "GHTYAJCE",
      "sid" => "mas_session_abc"
    }

    stub_request(:post, "https://auth.tween.im/oauth2/introspect")
      .with(body: hash_including("token" => "matrix_access_token"))
      .to_return(status: 200, body: mas_user_info.to_json)

    stub_request(:post, "https://auth.tween.im/oauth2/token")
      .to_return(status: 200, body: {
        access_token: "new_matrix_token_xyz789",
        token_type: "Bearer",
        expires_in: 300
      }.to_json)

    TepTokenService.define_singleton_method(:encode) { |*| "fake.tep.token" }

    result = @mas_client.exchange_matrix_token_for_tep(
      "matrix_access_token",
      "test_client",
      %w[ user:read wallet:pay ],
      { "launch_source" => "chat_bubble" },
      mas_user_info
    )

    assert_equal "tep.fake.tep.token", result[:access_token]
    assert_equal "Bearer", result[:token_type]
    assert_equal 86400, result[:expires_in]
    assert result[:refresh_token].present?
    assert_equal "@alice:tween.im", result[:user_id]
    assert result[:wallet_id].start_with?("wallet_")
    assert_equal "user:read wallet:pay", result[:scope]
    assert_equal "new_matrix_token_xyz789", result[:matrix_access_token]
    assert_equal 300, result[:matrix_expires_in]
    assert result[:delegated_session] == true
  ensure
    TepTokenService.define_singleton_method(:encode, TepTokenService.method(:encode))
  end

  test "#introspect_token returns user info when active" do
    mock_info = {
      "active" => true,
      "sub" => "@bob:tween.im",
      "email" => "bob@example.com"
    }

    stub_request(:post, "https://auth.tween.im/oauth2/introspect")
      .with(body: hash_including({ "token" => "test_token" }))
      .to_return(status: 200, body: mock_info.to_json)

    result = @mas_client.introspect_token("test_token")

    assert_equal "@bob:tween.im", result["sub"]
    assert result["active"]
  end

  test "#introspect_token raises error when inactive" do
    stub_request(:post, "https://auth.tween.im/oauth2/introspect")
      .to_return(status: 200, body: { "active" => false }.to_json)

    assert_raises(MasClientService::InvalidTokenError) do
      @mas_client.get_user_info("expired_token")
    end
  end

  test "#revoke_token calls revocation endpoint" do
    stub_request(:post, "https://auth.tween.im/oauth2/revoke")
      .to_return(status: 200)

    result = @mas_client.revoke_token("token_to_revoke")

    assert result
  end
end
