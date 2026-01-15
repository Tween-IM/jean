require "test_helper"

class TepTokenServiceTest < ActiveSupport::TestCase
  # TMCP Protocol Section 4.3: TEP Token Service tests
  # Updated for TMCP v1.5.0 with dual-token architecture

  setup do
    # Ensure we're using the consistent test key
    TepTokenService.reset_keys!
    @user_id = "@alice:tween.example"
    @miniapp_id = "ma_shop_001"
    @scopes = [ "user:read", "wallet:pay" ]
    @wallet_id = "tw_user_12345"
    @session_id = "session_xyz789"
    @miniapp_context = {
      "launch_source" => "chat_bubble",
      "room_id" => "!abc123:tween.example"
    }
    @user_context = {
      "display_name" => "Alice",
      "avatar_url" => "mxc://tween.example/avatar123"
    }
    @mas_session = {
      "active" => true,
      "refresh_token_id" => "rt_abc123"
    }
  end

  test "should encode and decode TEP token with v1.5.0 claims" do
    token = TepTokenService.encode(
      { user_id: @user_id, miniapp_id: @miniapp_id, user_context: @user_context },
      scopes: @scopes,
      wallet_id: @wallet_id,
      session_id: @session_id,
      miniapp_context: @miniapp_context,
      mas_session: @mas_session
    )

    assert_not_nil token

    payload = TepTokenService.decode(token)

    # Verify required JWT claims (TMCP Protocol Section 4.3)
    assert_equal TepTokenService::ISSUER, payload["iss"]
    assert_equal @user_id, payload["sub"]
    assert_equal @miniapp_id, payload["aud"]
    assert_not_nil payload["exp"]
    assert_not_nil payload["iat"]
    assert_not_nil payload["nbf"]
    assert_not_nil payload["jti"]

    # v1.5.0 specific claims
    assert_equal "tep_access_token", payload["token_type"]
    assert_equal @miniapp_id, payload["client_id"]
    assert_equal @miniapp_id, payload["azp"]
    assert_equal @scopes.join(" "), payload["scope"]
    assert_equal @wallet_id, payload["wallet_id"]
    assert_equal @session_id, payload["session_id"]
    assert_equal @miniapp_context, payload["miniapp_context"]
    assert_equal @user_context["display_name"], payload["user_context"]["display_name"]
    assert_equal true, payload["mas_session"]["active"]
  end

  test "should validate nbf (not before) claim" do
    before_test = Time.current.to_i
    token = TepTokenService.encode(
      { user_id: @user_id, miniapp_id: @miniapp_id }
    )
    after_test = Time.current.to_i

    payload = TepTokenService.decode(token)
    assert_not_nil payload["nbf"]
    assert_includes (before_test..after_test), payload["nbf"]
  end

  test "should reject token with invalid token_type" do
    token = TepTokenService.encode(
      { user_id: @user_id, miniapp_id: @miniapp_id }
    )

    # Decode and modify token_type
    decoded = JWT.decode(token, nil, false)
    payload = decoded[0]
    payload["token_type"] = "wrong_type"

    modified_token = JWT.encode(payload, TepTokenService.send(:private_key), "RS256")

    assert_raises JWT::DecodeError do
      TepTokenService.decode(modified_token)
    end
  end

  test "should use RS256 algorithm from whitelist" do
    token = TepTokenService.encode(
      { user_id: @user_id, miniapp_id: @miniapp_id }
    )

    decoded = JWT.decode(token, nil, false)
    headers = decoded.last

    assert_equal "RS256", headers["alg"]
    assert_equal TepTokenService::KEY_ID, headers["kid"]
  end

  test "should reject tokens with algorithms not in whitelist" do
    payload = {
      iss: TepTokenService::ISSUER,
      sub: @user_id,
      aud: @miniapp_id,
      exp: 1.hour.from_now.to_i,
      iat: Time.current.to_i,
      nbf: Time.current.to_i,
      jti: SecureRandom.uuid,
      token_type: "tep_access_token"
    }

    # Create token with HS256 (not in whitelist) using a string key
    invalid_token = JWT.encode(payload, "hmac_secret_key_string", "HS256")

    assert_raises JWT::DecodeError do
      TepTokenService.decode(invalid_token)
    end
  end

  test "should validate token expiration" do
    # Create token that expires immediately
    expired_token = TepTokenService.encode(
      { user_id: @user_id, miniapp_id: @miniapp_id },
      scopes: @scopes
    )

    # Manually modify expiration to past
    payload = TepTokenService.decode(expired_token)
    payload["exp"] = 1.day.ago.to_i

    # Re-encode with expired time (this is a test hack)
    expired_token = JWT.encode(payload, TepTokenService.private_key, TepTokenService::ALGORITHM)

    assert_raises JWT::ExpiredSignature do
      TepTokenService.decode(expired_token)
    end

    assert TepTokenService.expired?(expired_token)
  end

  test "should extract scopes from token" do
    token = TepTokenService.encode(
      { user_id: @user_id, miniapp_id: @miniapp_id },
      scopes: @scopes
    )

    extracted_scopes = TepTokenService.extract_scopes(token)
    assert_equal @scopes, extracted_scopes
  end

  test "should extract user_id from token" do
    token = TepTokenService.encode(
      { user_id: @user_id, miniapp_id: @miniapp_id }
    )

    extracted_user_id = TepTokenService.extract_user_id(token)
    assert_equal @user_id, extracted_user_id
  end

  test "should extract wallet_id from token" do
    token = TepTokenService.encode(
      { user_id: @user_id, miniapp_id: @miniapp_id },
      wallet_id: @wallet_id
    )

    extracted_wallet_id = TepTokenService.extract_wallet_id(token)
    assert_equal @wallet_id, extracted_wallet_id
  end

  test "should extract miniapp_id from token" do
    token = TepTokenService.encode(
      { user_id: @user_id, miniapp_id: @miniapp_id }
    )

    extracted_miniapp_id = TepTokenService.extract_miniapp_id(token)
    assert_equal @miniapp_id, extracted_miniapp_id
  end

  test "should validate token" do
    valid_token = TepTokenService.encode(
      { user_id: @user_id, miniapp_id: @miniapp_id }
    )

    assert TepTokenService.valid?(valid_token)
    assert_not TepTokenService.valid?("invalid.token.here")
  end

  test "should reject invalid issuer" do
    # Create token with wrong issuer
    payload = {
      iss: "https://fake.example.com",
      sub: @user_id,
      aud: @miniapp_id,
      exp: 1.hour.from_now.to_i,
      iat: Time.current.to_i,
      jti: SecureRandom.uuid
    }

    invalid_token = JWT.encode(payload, TepTokenService.private_key, TepTokenService::ALGORITHM)

    assert_raises JWT::InvalidIssuerError do
      TepTokenService.decode(invalid_token)
    end
  end

  test "should use RS256 algorithm" do
    token = TepTokenService.encode(
      { user_id: @user_id, miniapp_id: @miniapp_id }
    )

    # Decode without verification to check algorithm
    decoded = JWT.decode(token, nil, false)
    headers = decoded.last

    assert_equal "RS256", headers["alg"]
    assert_equal TepTokenService::KEY_ID, headers["kid"]
  end
end
