require "test_helper"

class TepTokenServiceTest < ActiveSupport::TestCase
  # TMCP Protocol Section 4.3: TEP Token Service tests

  setup do
    @user_id = "@alice:tween.example"
    @miniapp_id = "ma_shop_001"
    @scopes = [ "user:read", "wallet:pay" ]
    @wallet_id = "tw_user_12345"
    @session_id = "session_xyz789"
    @miniapp_context = {
      "launch_source" => "chat_bubble",
      "room_id" => "!abc123:tween.example"
    }
  end

  test "should encode and decode TEP token" do
    token = TepTokenService.encode(
      { user_id: @user_id, miniapp_id: @miniapp_id },
      scopes: @scopes,
      wallet_id: @wallet_id,
      session_id: @session_id,
      miniapp_context: @miniapp_context
    )

    assert_not_nil token

    payload = TepTokenService.decode(token)

    # Verify required JWT claims (TMCP Protocol Section 4.3)
    assert_equal TepTokenService::ISSUER, payload["iss"]
    assert_equal @user_id, payload["sub"]
    assert_equal @miniapp_id, payload["aud"]
    assert_not_nil payload["exp"]
    assert_not_nil payload["iat"]
    assert_not_nil payload["jti"]
    assert_equal @scopes.join(" "), payload["scope"]
    assert_equal @wallet_id, payload["wallet_id"]
    assert_equal @session_id, payload["session_id"]
    assert_equal @miniapp_context, payload["miniapp_context"]
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
