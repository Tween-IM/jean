class Api::V1::OauthController < ApplicationController
  # TMCP Protocol Section 4.2: Keycloak OAuth 2.0 + PKCE Integration
  include KeycloakTokenValidator

  skip_before_action :verify_authenticity_token, only: [ :authorize, :token, :callback ]

  # TMCP Protocol Section 4.2.1 - Authorization Request (redirect to Keycloak)
  def authorize
    # Get raw parameters to avoid recursion
    raw_params = request.request_parameters

    # Validate TMCP-specific parameters
    required_params = %w[response_type client_id redirect_uri scope state code_challenge code_challenge_method]
    missing_params = required_params.select { |param| raw_params[param].blank? }

    if missing_params.any?
      return render json: {
        error: "invalid_request",
        error_description: "Missing required parameters: #{missing_params.join(', ')}"
      }, status: :bad_request
    end

    # Validate response_type must be 'code'
    unless raw_params[:response_type] == "code"
      return render json: { error: "unsupported_response_type" }, status: :bad_request
    end

    # Validate code_challenge_method must be 'S256' (TMCP requirement)
    unless raw_params[:code_challenge_method] == "S256"
      return render json: {
        error: "invalid_request",
        error_description: "code_challenge_method must be S256"
      }, status: :bad_request
    end

    # Validate TMCP scopes
    requested_scopes = raw_params[:scope].split
    valid_scopes = %w[user:read user:read:extended user:read:contacts wallet:balance wallet:pay wallet:history messaging:send messaging:read storage:read storage:write]
    invalid_scopes = requested_scopes - valid_scopes

    if invalid_scopes.any?
      return render json: {
        error: "invalid_scope",
        error_description: "Invalid scopes: #{invalid_scopes.join(', ')}"
      }, status: :bad_request
    end

    # Validate mini-app exists and is active
    miniapp = MiniApp.find_by(app_id: raw_params[:client_id], status: :active)
    unless miniapp
      return render json: {
        error: "invalid_client",
        error_description: "Mini-app not found or inactive"
      }, status: :bad_request
    end

    # Store authorization request data for callback
    auth_request_id = SecureRandom.urlsafe_base64(32)
    session[:tmcp_auth_request] = {
      id: auth_request_id,
      client_id: raw_params[:client_id],
      redirect_uri: raw_params[:redirect_uri],
      scope: requested_scopes,
      state: raw_params[:state],
      code_challenge: raw_params[:code_challenge],
      code_challenge_method: raw_params[:code_challenge_method],
      miniapp_name: miniapp.name,
      miniapp_icon: miniapp.icon_url,
      created_at: Time.current
    }

    # Redirect to Keycloak authorization endpoint
    keycloak_url = "#{Rails.application.config.keycloak[:server_url]}/auth/realms/#{Rails.application.config.keycloak[:realm]}/protocol/openid-connect/auth"
    params = {
      client_id: Rails.application.config.keycloak[:client_id],
      redirect_uri: Rails.application.config.keycloak[:redirect_uri],
      response_type: "code",
      scope: "openid email profile",
      state: raw_params[:state],
      code_challenge: raw_params[:code_challenge],
      code_challenge_method: "S256"
    }

    redirect_to "#{keycloak_url}?#{params.to_query}", allow_other_host: true
  end

  # POST /api/v1/oauth/consent - Handle Keycloak callback
  def callback
    auth_hash = request.env["omniauth.auth"]
    
    if auth_hash.nil?
      return render json: { error: "auth_failure", message: "Authentication failed" }, status: :unauthorized
    end

    # Retrieve stored authorization request
    auth_request = session[:tmcp_auth_request]
    unless auth_request
      return render json: { error: "invalid_request", message: "Authorization request not found" }, status: :bad_request
    end

    # Validate state parameter
    unless params[:state] == auth_request["state"]
      return render json: { error: "invalid_state", message: "State parameter mismatch" }, status: :bad_request
    end

    # Get authorization code from Keycloak
    auth_code = params[:code]
    unless auth_code
      return render json: { error: "missing_code", message: "Authorization code not received" }, status: :bad_request
    end

    # Exchange authorization code for tokens
    token_response = exchange_code_for_tokens(auth_code, auth_request)

    # Generate TEP token
    access_token = TepTokenService.encode(
      {
        user_id: token_response[:user_id],
        miniapp_id: auth_request["client_id"]
      },
      scopes: auth_request["scope"],
      wallet_id: token_response[:wallet_id],
      session_id: SecureRandom.uuid,
      miniapp_context: {
        launch_source: "oauth_flow",
        room_id: auth_request["room_id"]
      }
    )

    refresh_token = SecureRandom.urlsafe_base64(32)

    # Store refresh token
    Rails.cache.write("refresh_token:#{refresh_token}",
      {
        user_id: token_response[:user_id],
        miniapp_id: auth_request["client_id"],
        scope: auth_request["scope"],
        token_data: token_response
      },
      expires_in: 30.days
    )

    # Clean up auth request
    session.delete(:tmcp_auth_request)

    # Redirect back to mini-app with tokens
    redirect_uri = "#{auth_request['redirect_uri']}?code=#{auth_code}&state=#{auth_request['state']}"
    redirect_to redirect_uri, allow_other_host: true
  end

  # TMCP Protocol Section 4.2.5 - Token Exchange
  def token
    raw_params = request.request_parameters

    if raw_params[:grant_type] == "authorization_code"
      # Handle Keycloak authorization code flow
      auth_code = raw_params[:code]
      auth_request_id = raw_params[:state] # Using state as auth request identifier
      
      # Retrieve stored auth request
      auth_request = session[:tmcp_auth_request] || Rails.cache.read("auth_request:#{auth_request_id}")
      unless auth_request
        return render json: {
          error: "invalid_grant",
          error_description: "Authorization request not found"
        }, status: :bad_request
      end

      # Exchange code for tokens
      token_response = exchange_code_for_tokens(auth_code, auth_request)

      # Generate TEP token
      access_token = TepTokenService.encode(
        {
          user_id: token_response[:user_id],
          miniapp_id: auth_request["client_id"]
        },
        scopes: auth_request["scope"],
        wallet_id: token_response[:wallet_id],
        session_id: SecureRandom.uuid,
        miniapp_context: {
          launch_source: "oauth_flow",
          room_id: auth_request["room_id"]
        }
      )

      refresh_token = SecureRandom.urlsafe_base64(32)

      # Store refresh token
      Rails.cache.write("refresh_token:#{refresh_token}",
        {
          user_id: token_response[:user_id],
          miniapp_id: auth_request["client_id"],
          scope: auth_request["scope"],
          token_data: token_response
        },
        expires_in: 30.days
      )

      render json: {
        access_token: access_token,
        token_type: "Bearer",
        expires_in: 3600,
        refresh_token: refresh_token,
        scope: auth_request["scope"].join(" "),
        user_id: token_response[:user_id],
        wallet_id: token_response[:wallet_id]
      }

    elsif raw_params[:grant_type] == "refresh_token"
      # Handle refresh token
      refresh_token = raw_params[:refresh_token]
      refresh_data = Rails.cache.read("refresh_token:#{refresh_token}")

      unless refresh_data
        return render json: {
          error: "invalid_grant",
          error_description: "Refresh token expired or invalid"
        }, status: :bad_request
      end

      # Generate new TEP token
      access_token = TepTokenService.encode(
        {
          user_id: refresh_data["user_id"],
          miniapp_id: refresh_data["miniapp_id"]
        },
        scopes: refresh_data["scope"]
      )

      new_refresh_token = SecureRandom.urlsafe_base64(32)

      # Update refresh token data
      Rails.cache.write("refresh_token:#{new_refresh_token}", refresh_data, expires_in: 30.days)

      render json: {
        access_token: access_token,
        token_type: "Bearer",
        expires_in: 3600,
        refresh_token: new_refresh_token,
        scope: refresh_data["scope"].join(" ")
      }
    else
      render json: { error: "unsupported_grant_type" }, status: :bad_request
    end
  end

  private

  def exchange_code_for_tokens(auth_code, auth_request)
    # Exchange authorization code for access token from Keycloak
    keycloak_token_url = "#{Rails.application.config.keycloak[:server_url]}/auth/realms/#{Rails.application.config.keycloak[:realm]}/protocol/openid-connect/token"
    
    response = Faraday.post(keycloak_token_url) do |req|
      req.body = {
        grant_type: "authorization_code",
        code: auth_code,
        redirect_uri: Rails.application.config.keycloak[:redirect_uri],
        client_id: Rails.application.config.keycloak[:client_id],
        client_secret: Rails.application.config.keycloak[:client_secret]
      }.to_query
      req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
    end

    if response.status != 200
      raise "Keycloak token exchange failed: #{response.body}"
    end

    token_data = JSON.parse(response.body)
    
    # Validate and extract user information
    id_token = token_data["id_token"]
    unless id_token
      raise "No ID token received from Keycloak"
    end

    # Validate ID token
    payload = KeycloakTokenValidator.validate_token(id_token)
    
    # Extract user information
    user_id = payload["sub"]
    email = payload["email"]
    
    # Find or create user
    user = User.find_or_create_by!(matrix_user_id: user_id) do |u|
      u.matrix_username = payload["preferred_username"] || email.split('@').first
      u.matrix_homeserver = Rails.application.config.keycloak[:realm]
      u.status = :active
    end

    {
      user_id: user.matrix_user_id,
      wallet_id: user.wallet_id,
      access_token: token_data["access_token"],
      refresh_token: token_data["refresh_token"],
      expires_in: token_data["expires_in"]
    }
  end
end
