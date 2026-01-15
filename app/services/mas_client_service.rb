class MasClientService
  ALLOWED_ALGORITHMS = %w[RS256 RS384 RS512].freeze

  class MasError < StandardError; end
  class TokenRefreshError < MasError; end
  class InvalidTokenError < MasError; end

  attr_reader :client_id, :client_secret, :token_url, :introspection_url, :revocation_url

  def initialize(config = {})
    @client_id = config[:client_id] || ENV["MAS_CLIENT_ID"]
    @client_secret = config[:client_secret] || ENV["MAS_CLIENT_SECRET"]
    @client_secret_file = config[:client_secret_file] || ENV["MAS_CLIENT_SECRET_FILE"]
    @token_url = config[:token_url] || ENV["MAS_TOKEN_URL"] || "https://mas.tween.example/oauth2/token"
    @introspection_url = config[:introspection_url] || ENV["MAS_INTROSPECTION_URL"] || "https://mas.tween.example/oauth2/introspect"
    @revocation_url = config[:revocation_url] || ENV["MAS_REVOCATION_URL"] || "https://mas.tween.example/oauth2/revoke"
    @default_scopes = config[:default_scopes] || [
      "openid",
      "urn:matrix:org.matrix.msc2967.client:api:*"
    ]
    @token_cache_ttl = 240

    load_client_secret
  end

  def client_credentials_grant
    response = http_client.post(@token_url) do |req|
      req.headers["Content-Type"] = "application/x-www-form-urlencoded"
      req.body = URI.encode_www_form({
        grant_type: "client_credentials",
        client_id: @client_id,
        client_secret: @client_secret,
        scope: @default_scopes.join(" ")
      })
    end

    unless response.success?
      raise MasError, "Client credentials grant failed: #{response.body}"
    end

    token_data = JSON.parse(response.body)
    {
      access_token: token_data["access_token"],
      token_type: token_data["token_type"],
      expires_in: token_data["expires_in"],
      expires_at: Time.current.to_i + token_data["expires_in"]
    }
  end

  def refresh_access_token(refresh_token)
    response = http_client.post(@token_url) do |req|
      req.headers["Content-Type"] = "application/x-www-form-urlencoded"
      req.body = URI.encode_www_form({
        grant_type: "urn:ietf:params:oauth:grant-type:refresh_token",
        refresh_token: refresh_token,
        client_id: @client_id,
        client_secret: @client_secret
      })
    end

    unless response.success?
      raise TokenRefreshError, "Token refresh failed: #{response.body}"
    end

    token_data = JSON.parse(response.body)
    {
      access_token: token_data["access_token"],
      token_type: token_data["token_type"],
      expires_in: token_data["expires_in"],
      refresh_token: token_data["refresh_token"],
      expires_at: Time.current.to_i + token_data["expires_in"]
    }
  end

  def introspect_token(access_token)
    response = http_client.post(@introspection_url) do |req|
      req.headers["Content-Type"] = "application/x-www-form-urlencoded"
      req.body = URI.encode_www_form({
        token: access_token,
        client_id: @client_id,
        client_secret: @client_secret
      })
    end

    unless response.success?
      raise MasError, "Token introspection failed: #{response.body}"
    end

    JSON.parse(response.body)
  end

  def refresh_access_token_for_matrix(current_token)
    response = http_client.post(@token_url) do |req|
      req.headers["Content-Type"] = "application/x-www-form-urlencoded"
      req.body = URI.encode_www_form({
        grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
        subject_token: current_token,
        subject_token_type: "urn:ietf:params:oauth:token-type:access_token",
        requested_token_type: "urn:ietf:params:oauth:token-type:access_token",
        scope: @default_scopes.join(" "),
        client_id: @client_id,
        client_secret: @client_secret
      })
    end

    unless response.success?
      Rails.logger.warn "Matrix token exchange failed: #{response.body}"
      return {
        access_token: current_token,
        token_type: "Bearer",
        expires_in: 300
      }
    end

    token_data = JSON.parse(response.body)
    {
      access_token: token_data["access_token"],
      token_type: token_data["token_type"],
      expires_in: token_data["expires_in"]
    }
  end

  def revoke_token(token, token_type_hint = nil)
    body = {
      token: token,
      client_id: @client_id,
      client_secret: @client_secret
    }
    body[:token_type_hint] = token_type_hint if token_type_hint

    response = http_client.post(@revocation_url) do |req|
      req.headers["Content-Type"] = "application/x-www-form-urlencoded"
      req.body = URI.encode_www_form(body)
    end

    unless response.success?
      Rails.logger.warn "Token revocation failed: #{response.body}"
    end

    true
  end

  def get_user_info(access_token)
    introspect_token(access_token).tap do |info|
      if info["active"] != true
        raise InvalidTokenError, "Token is not active"
      end
    end
  end

  def exchange_matrix_token_for_tep(matrix_access_token, miniapp_id, scopes, miniapp_context = {}, introspection_response = nil)
    mas_user_info = introspection_response || get_user_info(matrix_access_token)
    user_id = mas_user_info["sub"]
wallet_id = user_id ? "tw_#{user_id.gsub(/[@:]/, '_')}" : "tw_unknown"
    session_id = generate_session_id

    device_id = mas_user_info.dig("device_id") || "unknown"
    mas_session_id = mas_user_info.dig("sid") || "unknown"

    tep_claims = {
      iss: TMCP.config[:jwt_issuer],
      sub: user_id,
      aud: miniapp_id,
      exp: Time.current.to_i + 86400,
      iat: Time.current.to_i,
      nbf: Time.current.to_i,
      jti: SecureRandom.uuid,
      token_type: "tep_access_token",
      client_id: miniapp_id,
      azp: miniapp_id,
      scope: scopes.join(" "),
      wallet_id: wallet_id,
      session_id: session_id,
      user_context: {
        display_name: mas_user_info["display_name"],
        avatar_url: mas_user_info["avatar_url"]
      },
      miniapp_context: miniapp_context,
      mas_session: {
        active: true,
        refresh_token_id: "rt_#{SecureRandom.alphanumeric(16)}"
      },
      delegated_from: "matrix_session",
      matrix_session_ref: {
        device_id: device_id,
        session_id: mas_session_id
      },
      approval_history: build_approval_history(user_id, miniapp_id, scopes),
      authorization_context: build_authorization_context({ miniapp_context: miniapp_context })
    }

    tep_token = TepTokenService.encode(tep_claims)
    tep_refresh_token = "rt_#{SecureRandom.alphanumeric(24)}"

    Rails.cache.write("refresh_token:#{tep_refresh_token}", {
      user_id: user_id,
      miniapp_id: miniapp_id,
      scope: scopes,
      created_at: Time.current.to_i
    }, expires_in: 30.days)

    matrix_token_response = refresh_access_token_for_matrix(matrix_access_token)

    {
      access_token: "tep.#{tep_token}",
      token_type: "Bearer",
      expires_in: 86400,
      refresh_token: tep_refresh_token,
      scope: scopes.join(" "),
      user_id: user_id,
      wallet_id: wallet_id,
      matrix_access_token: matrix_token_response[:access_token],
      matrix_expires_in: matrix_token_response[:expires_in],
      delegated_session: true
    }
  end

  def validate_mas_token_for_matrix_operations(access_token)
    info = introspect_token(access_token)

    unless info["active"]
      raise InvalidTokenError, "MAS access token is not active"
    end

    if info["exp"] && Time.current.to_i > info["exp"]
      raise InvalidTokenError, "MAS access token has expired"
    end

    info
  end

  private

  def http_client
    @http_client ||= Faraday.new(request: { timeout: 30 }, ssl: { verify: true })
  end

  def load_client_secret
    if @client_secret_file && File.exist?(@client_secret_file)
      @client_secret = File.read(@client_secret_file).strip
    elsif !@client_secret
      raise MasError, "MAS client secret not configured"
    end
  end

  def generate_session_id
    "sess_#{SecureRandom.alphanumeric(24)}"
  end

  def build_approval_history(user_id, miniapp_id, scopes)
    return [] if user_id.nil? || miniapp_id.nil?

    approvals = AuthorizationApproval.where(
      user_id: user_id,
      miniapp_id: miniapp_id
    ).where(scope: scopes).order(approved_at: :desc).limit(10)

    approvals.map do |approval|
      {
        scope: approval.scope,
        approved_at: approval.approved_at.iso8601,
        approval_method: approval.approval_method || "initial"
      }
    end
  rescue ActiveRecord::StatementInvalid
    []
  end

  def build_authorization_context(payload)
    room_id = payload.dig(:miniapp_context, :room_id)
    return nil if room_id.nil?

    {
      room_id: room_id,
      roles: payload.dig(:authorization_context, :roles) || [ "member" ],
      permissions: build_permissions(payload[:miniapp_context])
    }
  end

  def build_permissions(miniapp_context)
    room_id = miniapp_context[:room_id]
    return {} if room_id.nil?

    {
      can_send_messages: true,
      can_invite_users: false,
      can_edit_messages: false,
      can_delete_messages: false,
      can_add_reactions: true
    }
  end
end
