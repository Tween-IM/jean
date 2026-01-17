class MasClientService
  ALLOWED_ALGORITHMS = %w[RS256 RS384 RS512].freeze

  class MasError < StandardError; end
  class TokenRefreshError < MasError; end
  class InvalidTokenError < MasError; end
  class InvalidCredentialsError < MasError; end

  attr_reader :client_id, :client_secret, :token_url, :introspection_url, :revocation_url

  def initialize(config = {})
    @client_id = config[:client_id] || ENV["MAS_CLIENT_ID"]
    @client_secret = config[:client_secret] || ENV["MAS_CLIENT_SECRET"]
    @client_secret_file = config[:client_secret_file] || ENV["MAS_CLIENT_SECRET_FILE"]
    @token_url = config[:token_url] || ENV["MAS_TOKEN_URL"] || "https://mas.tween.example/oauth2/token"
    @introspection_url = config[:introspection_url] || ENV["MAS_INTROSPECTION_URL"] || "https://mas.tween.example/oauth2/introspect"
    @revocation_url = config[:revocation_url] || ENV["MAS_REVOCATION_URL"] || "https://mas.tween.example/oauth2/revoke"
    @matrix_domain = config[:matrix_domain] || ENV["MATRIX_DOMAIN"] || "tween.im"
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

    parse_mas_error(response) unless response.success?

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

    parse_mas_error(response) unless response.success?

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

  def query_users_by_name(search_term, limit = 10)
    # Matrix user directory search through homeserver
    # This would typically call the homeserver's user directory API
    # For now, return mock data as the Matrix homeserver integration isn't implemented
    Rails.logger.info "Querying Matrix users by name: #{search_term}, limit: #{limit}"

    # Mock user directory results
    # In production, this would call: GET /_matrix/client/v3/user_directory/search
    mock_results = [
      {
        user_id: "@alice:#{@matrix_domain}",
        display_name: "Alice Smith",
        avatar_url: nil
      },
      {
        user_id: "@bob:#{@matrix_domain}",
        display_name: "Bob Johnson",
        avatar_url: nil
      },
      {
        user_id: "@charlie:#{@matrix_domain}",
        display_name: "Charlie Brown",
        avatar_url: nil
      }
    ].select { |user| user[:display_name].downcase.include?(search_term.downcase) || user[:user_id].include?(search_term) }

    {
      results: mock_results.take(limit),
      limited: mock_results.size > limit,
      total_count: mock_results.size
    }
  end

  # Send message to Matrix room as Application Service
  def send_message_to_room(access_token, room_id, message, event_type = "m.room.message", msgtype = "m.text")
    # Matrix AS sends messages using Client-Server API
    # PUT /_matrix/client/v3/rooms/{roomId}/send/{eventType}/{txnId}

    txn_id = SecureRandom.hex(8)
    event_content = {
      msgtype: msgtype,
      body: message
    }

    # For custom event types, use different content structure
    if event_type != "m.room.message"
      event_content = message.is_a?(Hash) ? message : { body: message }
    end

    # Use production Matrix homeserver URL
    homeserver_url = ENV["MATRIX_API_URL"] || "https://core.tween.im"

    response = http_client.put("#{homeserver_url}/_matrix/client/v3/rooms/#{CGI.escape(room_id)}/send/#{CGI.escape(event_type)}/#{txn_id}") do |req|
      req.headers["Authorization"] = "Bearer #{access_token}"
      req.headers["Content-Type"] = "application/json"
      req.body = event_content.to_json
    end

    if response.success?
      result = JSON.parse(response.body)
      event_id = result["event_id"]
      Rails.logger.info "Matrix message sent successfully. Room: #{room_id}, Event ID: #{event_id}"
      { success: true, event_id: event_id }
    else
      Rails.logger.error "Failed to send Matrix message. Room: #{room_id}, Status: #{response.status}, Body: #{response.body}"
      { success: false, error: response.status, message: response.body }
    end
  rescue StandardError => e
    Rails.logger.error "Error sending Matrix message: #{e.message}"
    { success: false, error: "internal_error", message: e.message }
  end

    response = http_client.put("#{homeserver_url}/_matrix/client/v3/rooms/#{CGI.escape(room_id)}/send/#{CGI.escape(event_type)}/#{txn_id}") do |req|
      req.headers["Authorization"] = "Bearer #{access_token}"
      req.headers["Content-Type"] = "application/json"
      req.body = {
        content: event_content,
        type: event_type
      }.to_json
    end

    if response.success?
      event_id = JSON.parse(response.body)["event_id"]
      Rails.logger.info "Matrix message sent successfully. Room: #{room_id}, Event ID: #{event_id}"
      { success: true, event_id: event_id }
    else
      Rails.logger.error "Failed to send Matrix message. Room: #{room_id}, Status: #{response.status}, Body: #{response.body}"
      { success: false, error: response.status, message: response.body }
    end
  rescue StandardError => e
    Rails.logger.error "Error sending Matrix message: #{e.message}"
    { success: false, error: "internal_error", message: e.message }
end

  def exchange_matrix_token_for_tep(matrix_access_token, miniapp_id, scopes, miniapp_context = {}, introspection_response = nil)
    mas_user_info = introspection_response || get_user_info(matrix_access_token)
    mas_user_id = mas_user_info["sub"]
    mas_username = mas_user_info["username"]

    # Construct Matrix user ID for PROTO.md compliance
    matrix_user_id = if mas_username.to_s.strip.empty?
                       mas_user_id # fallback to internal ID
    else
                       "@#{mas_username}:#{@matrix_domain}"
    end

    wallet_id = if mas_user_id.to_s.strip.empty?
                  "tw_unknown"
    else
                  "tw_#{mas_user_id.gsub(/[@:]/, '_')}"
    end

    session_id = generate_session_id

    device_id = mas_user_info.dig("device_id") || "unknown"
    mas_session_id = mas_user_info.dig("sid") || "unknown"

    tep_payload = {
      user_id: matrix_user_id, # Use Matrix user ID for TEP token claims
      miniapp_id: miniapp_id,
      user_context: {
        display_name: mas_user_info["display_name"],
        avatar_url: mas_user_info["avatar_url"]
      }
    }

    tep_token = TepTokenService.encode(
      tep_payload,
      scopes: scopes,
      wallet_id: wallet_id,
      session_id: session_id,
      miniapp_context: miniapp_context,
      mas_session: {
        active: true,
        refresh_token_id: "rt_#{SecureRandom.alphanumeric(16)}"
      },
      authorization_context: build_authorization_context({ miniapp_context: miniapp_context }),
      approval_history: build_approval_history(mas_user_id, miniapp_id, scopes),
      delegated_from: "matrix_session",
      matrix_session_ref: {
        device_id: device_id,
        session_id: mas_session_id
      }
    )
    tep_refresh_token = "rt_#{SecureRandom.alphanumeric(24)}"

    Rails.cache.write("refresh_token:#{tep_refresh_token}", {
      user_id: mas_user_id, # Use internal ID for refresh token cache
      miniapp_id: miniapp_id,
      scope: scopes,
      created_at: Time.current.to_i
    }, expires_in: 30.days)

    new_matrix_token = refresh_access_token_for_matrix(matrix_access_token)

    # Auto-register user in wallet service during TEP token issuance
    begin
      WalletService.ensure_user_registered(matrix_user_id, matrix_access_token)
    rescue StandardError => e
      # Log but don't fail TEP token issuance
      Rails.logger.warn "Failed to register user #{matrix_user_id} in wallet service during token exchange: #{e.message}"
    end

    {
      access_token: "tep.#{tep_token}",
      token_type: "Bearer",
      expires_in: 86400,
      refresh_token: tep_refresh_token,
      scope: scopes.join(" "),
      user_id: matrix_user_id, # Return Matrix user ID for PROTO.md compliance
      wallet_id: wallet_id,
      matrix_access_token: new_matrix_token[:access_token],
      matrix_expires_in: new_matrix_token[:expires_in],
      delegated_session: true
    }
  end

  def validate_mas_token_for_matrix_operations(access_token)
    info = introspect_token(access_token)

    unless info["active"]
      raise InvalidTokenError, "MAS access token is not active"
    end

    if info["exp"] && Time.current.to_i >= info["exp"]
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

  def parse_mas_error(response)
    begin
      error_data = JSON.parse(response.body)
      mas_error = error_data["error"]
      mas_description = error_data["error_description"]

      case mas_error
      when "invalid_client"
        raise InvalidCredentialsError, "Matrix authentication service error"
      when "invalid_token"
        raise InvalidTokenError, mas_description || "Matrix token is invalid or expired"
      else
        raise MasError, mas_description || "Matrix authentication service error"
      end
    rescue JSON::ParserError
      raise MasError, "Matrix authentication service error"
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
  rescue ActiveRecord::StatementInvalid => e
    Rails.logger.warn "Failed to fetch approval history: #{e.message}"
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
