class TepTokenService
  # TMCP Protocol Section 4.3: TEP Token Structure
  # Updated for v1.5.0 with complete claim set

  ALGORITHM ||= TMCP.config[:jwt_algorithm]
  ISSUER ||= TMCP.config[:jwt_issuer]
  KEY_ID ||= TMCP.config[:jwt_key_id]

  ALLOWED_ALGORITHMS = %w[RS256 RS384 RS512].freeze

  class << self
    def private_key
      @private_key ||= load_or_generate_private_key
    end

    def public_key
      @public_key ||= private_key.public_key
    end

    def load_or_generate_private_key
      if ENV["TMCP_PRIVATE_KEY"].present?
        OpenSSL::PKey::RSA.new(ENV["TMCP_PRIVATE_KEY"])
      else
        generate_private_key
      end
    end

    def generate_private_key
      OpenSSL::PKey::RSA.new(2048)
    end

    def reset_keys!
      @private_key = nil
      @public_key = nil
    end
  end

  class << self
    def encode(payload, scopes: [], wallet_id: nil, session_id: nil, miniapp_context: {}, mas_session: nil)
      now = Time.current.to_i

      jwt_payload = {
        iss: ISSUER,
        sub: payload[:user_id],
        aud: payload[:miniapp_id],
        exp: now + 86400,
        iat: now,
        nbf: now,
        jti: SecureRandom.uuid,
        token_type: "tep_access_token",
        client_id: payload[:miniapp_id],
        azp: payload[:miniapp_id],
        scope: scopes.join(" "),
        wallet_id: wallet_id,
        session_id: session_id,
        miniapp_context: miniapp_context,
        user_context: payload[:user_context] || {},
        mas_session: mas_session || { active: true }
      }

      headers = { kid: KEY_ID }

      JWT.encode(jwt_payload, private_key, ALGORITHM, headers)
    end

    def decode(token)
      begin
        decoded = JWT.decode(token, public_key, true, {
          algorithms: ALLOWED_ALGORITHMS,
          verify_iss: true,
          verify_aud: true,
          verify_exp: true,
          verify_nbf: true,
          verify_iat: true
        })
        payload = decoded[0]
        headers = decoded[1]

        validate_issuer!(payload)
        validate_audience!(payload)
        validate_token_type!(payload)
        validate_expiration!(payload)
        validate_not_before!(payload)

        payload
      rescue JWT::ExpiredSignature
        raise JWT::ExpiredSignature.new("TEP token has expired")
      rescue JWT::InvalidIssuerError
        raise JWT::InvalidIssuerError.new("Invalid TEP token issuer")
      rescue JWT::InvalidAudError
        raise JWT::InvalidAudError.new("Invalid TEP token audience")
      rescue JWT::InvalidIatError
        raise JWT::InvalidIatError.new("Invalid TEP token issued at time")
      rescue JWT::DecodeError => e
        raise JWT::DecodeError.new("Invalid TEP token: #{e.message}")
      end
    end

    def valid?(token)
      decode(token)
      true
    rescue JWT::DecodeError
      false
    end

    def extract_scopes(token)
      payload = decode(token)
      payload["scope"]&.split(" ") || []
    end

    def extract_user_id(token)
      payload = decode(token)
      payload["sub"]
    end

    def extract_wallet_id(token)
      payload = decode(token)
      payload["wallet_id"]
    end

    def extract_miniapp_id(token)
      payload = decode(token)
      payload["aud"]
    end

    def expired?(token)
      payload = decode(token)
      Time.at(payload["exp"]) < Time.current
    rescue
      true
    end

    def validate_algorithm!(headers)
      alg = headers["alg"]
      unless ALLOWED_ALGORITHMS.include?(alg)
        raise JWT::DecodeError.new(
          "Invalid algorithm '#{alg}'. Allowed: #{ALLOWED_ALGORITHMS.join(', ')}"
        )
      end
     end

    def validate_issuer!(payload)
      return if payload["iss"] == ISSUER
      raise JWT::InvalidIssuerError.new("Invalid issuer. Expected: #{ISSUER}")
    end

    def validate_audience!(payload)
      return if payload["aud"].present?
      raise JWT::InvalidAudError.new("Missing audience claim")
    end

    def validate_token_type!(payload)
      expected_type = "tep_access_token"
      actual_type = payload["token_type"]
      return if actual_type == expected_type
      raise JWT::DecodeError.new(
        "Invalid token_type. Expected: #{expected_type}, got: #{actual_type}"
      )
    end

    def validate_expiration!(payload)
      exp = payload["exp"]
      return if exp.nil? || Time.current.to_i < exp
      raise JWT::ExpiredSignature.new("Token has expired")
    end

    def validate_not_before!(payload)
      nbf = payload["nbf"]
      return if nbf.nil? || Time.current.to_i >= nbf
      raise JWT::InvalidIatError.new("Token is not yet valid (nbf claim)")
    end
  end
end
