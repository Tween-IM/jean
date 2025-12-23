# Keycloak OAuth 2.0 + OpenID Connect Configuration for TMCP
# TMCP Protocol Section 16.10: Keycloak Integration

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :keycloak_open_id,
    Rails.application.config.keycloak[:server_url],
    Rails.application.config.keycloak[:realm],
    client_id: Rails.application.config.keycloak[:client_id],
    client_secret: Rails.application.config.keycloak[:client_secret],
    callback_path: "/api/v1/oauth2/callback",
    scope: "openid email profile",
    response_type: "code",
    pkce: :required,
    auth_server_url: "#{Rails.application.config.keycloak[:server_url]}/auth",
    ssl_verify: true
end

# Custom OmniAuth strategy for Keycloak integration
OmniAuth.config.add_camelization "keycloak", "Keycloak"

# Keycloak token validation
module KeycloakTokenValidator
  def self.validate_token(token)
    # In production, this would call Keycloak's token introspection endpoint
    # For now, we'll use a mock validation that checks token structure
    begin
      decoded = JWT.decode(token, nil, false)
      payload = decoded.first
      
      # Basic validation
      required_claims = %w[iss sub aud exp iat jti]
      missing_claims = required_claims - payload.keys
      
      if missing_claims.any?
        raise "Missing required claims: #{missing_claims.join(', ')}"
      end
      
      # Validate expiration
      if Time.at(payload["exp"]) < Time.current
        raise "Token expired"
      end
      
      payload
    rescue JWT::DecodeError => e
      raise "Invalid token: #{e.message}"
    end
  end
end