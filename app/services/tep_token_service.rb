class TepTokenService
  # TMCP Protocol Section 4.3: TEP Token Structure

  ALGORITHM ||= TMCP.config[:jwt_algorithm]
  ISSUER ||= TMCP.config[:jwt_issuer]
  KEY_ID ||= TMCP.config[:jwt_key_id]

  class << self
    def private_key
      @private_key ||= OpenSSL::PKey::RSA.new(ENV["TMCP_PRIVATE_KEY"] || generate_private_key)
    end

    def public_key
      private_key.public_key
    end
  end

  class << self
    def encode(payload, scopes: [], wallet_id: nil, session_id: nil, miniapp_context: {})
      # TMCP Protocol Section 4.3: Required JWT claims
      now = Time.current.to_i

      jwt_payload = {
        iss: ISSUER,                    # Issuer
        sub: payload[:user_id],         # Subject (Matrix User ID)
        aud: payload[:miniapp_id],      # Audience (Mini-App ID)
        exp: now + 3600,               # Expiration (1 hour)
        iat: now,                      # Issued at
        jti: SecureRandom.uuid,        # JWT ID
        scope: scopes.join(" "),       # Granted scopes
        wallet_id: wallet_id,          # User's wallet ID
        session_id: session_id,        # Session identifier
        miniapp_context: miniapp_context # Launch context
      }

      # Add header with key ID
      headers = { kid: KEY_ID }

      JWT.encode(jwt_payload, private_key, ALGORITHM, headers)
    end

    def decode(token)
      # Decode and verify JWT
      begin
        decoded = JWT.decode(token, public_key, true, { algorithm: ALGORITHM })
        payload = decoded.first
        headers = decoded.last

        # Validate issuer and key ID
        unless payload["iss"] == ISSUER && headers["kid"] == KEY_ID
          raise JWT::InvalidIssuerError.new("Invalid issuer or key ID")
        end

        payload
      rescue JWT::ExpiredSignature
        raise JWT::ExpiredSignature.new("TEP token has expired")
      rescue JWT::InvalidIssuerError
        raise JWT::InvalidIssuerError.new("Invalid TEP token issuer")
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

    private

    def generate_private_key
      # Generate RSA key pair for development (NEVER use in production)
      key = OpenSSL::PKey::RSA.new(2048)
      key.to_pem
    end
  end
end
