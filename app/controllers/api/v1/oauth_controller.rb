class Api::V1::OauthController < ApplicationController
  # TMCP Protocol Section 4.2: Independent OAuth 2.0 + PKCE Implementation

  skip_before_action :verify_authenticity_token, only: [ :authorize, :token ]

  # TMCP Protocol Section 4.2.1 - Authorization Request
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

    # For TMCP, we implement user consent directly (no external OAuth provider)
    # Store authorization request data
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

    # Return consent screen data (TMCP Protocol Section 4.2.3)
    render json: {
      auth_request_id: auth_request_id,
      miniapp: {
        id: miniapp.app_id,
        name: miniapp.name,
        developer: miniapp.developer_name,
        icon_url: miniapp.icon_url,
        verified: miniapp.classification == "verified" || miniapp.classification == "official"
      },
      requested_scopes: requested_scopes.map do |scope|
        {
          scope: scope,
          description: scope_description(scope),
          sensitivity: scope_sensitivity(scope),
          note: scope_note(scope)
        }
      end,
      expires_in: 300 # 5 minutes
    }, status: :ok
  end

  # POST /api/v1/oauth/consent - Handle user consent response
  def consent
    raw_params = request.request_parameters

    auth_request_id = raw_params[:auth_request_id]
    approved = raw_params[:approved] == "true"

    # Retrieve authorization request
    auth_request = session[:tmcp_auth_request]
    unless auth_request && auth_request["id"] == auth_request_id
      return render json: { error: "invalid_request", message: "Authorization request not found" }, status: :bad_request
    end

    session.delete(:tmcp_auth_request)

    if approved
      # User approved - create authorization code
      tmcp_code = generate_tmcp_code(auth_request)

      # Redirect back to mini-app with authorization code
      redirect_uri = "#{auth_request['redirect_uri']}?code=#{tmcp_code}&state=#{auth_request['state']}"
      redirect_to redirect_uri, allow_other_host: true
    else
      # User denied - redirect with error
      redirect_uri = "#{auth_request['redirect_uri']}?error=access_denied&state=#{auth_request['state']}"
      redirect_to redirect_uri, allow_other_host: true
    end
  end

  # TMCP Protocol Section 4.2.5 - Token Exchange
  def token
    raw_params = request.request_parameters

    if raw_params[:grant_type] == "authorization_code"
      # Handle TMCP authorization code flow
      tmcp_code = raw_params[:code]
      tmcp_data = Rails.cache.read("tmcp_code:#{tmcp_code}")

      unless tmcp_data
        return render json: {
          error: "invalid_grant",
          error_description: "TMCP authorization code expired or invalid"
        }, status: :bad_request
      end

      # Verify code verifier matches challenge (PKCE validation)
      unless valid_pkce?(tmcp_data["code_challenge"], raw_params[:code_verifier])
        return render json: {
          error: "invalid_grant",
          error_description: "Code verifier does not match challenge"
        }, status: :bad_request
      end

      # For TMCP independent OAuth, we need user authentication
      # In a real implementation, this would happen during the consent flow
      # For now, create a mock authenticated user
      user = ensure_authenticated_user

      # Generate TEP token (TMCP Protocol Section 4.3)
      access_token = TepTokenService.encode(
        {
          user_id: user.matrix_user_id,
          miniapp_id: tmcp_data["client_id"]
        },
        scopes: tmcp_data["scope"],
        wallet_id: user.wallet_id,
        session_id: SecureRandom.uuid,
        miniapp_context: {
          launch_source: "oauth_flow",
          room_id: tmcp_data["room_id"]
        }
      )

      refresh_token = SecureRandom.urlsafe_base64(32)

      # Store refresh token
      Rails.cache.write("refresh_token:#{refresh_token}",
        {
          user_id: user.matrix_user_id,
          miniapp_id: tmcp_data["client_id"],
          scope: tmcp_data["scope"]
        },
        expires_in: 30.days
      )

      # Clean up codes
      Rails.cache.delete("tmcp_code:#{tmcp_code}")

      render json: {
        access_token: access_token,
        token_type: "Bearer",
        expires_in: 3600,
        refresh_token: refresh_token,
        scope: tmcp_data["scope"].join(" "),
        user_id: user.matrix_user_id,
        wallet_id: user.wallet_id
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

  def generate_tmcp_code(auth_request)
    code = SecureRandom.urlsafe_base64(32)

    # Store TMCP code with authorization data
    Rails.cache.write("tmcp_code:#{code}", auth_request, expires_in: 10.minutes)

    code
  end

  def valid_pkce?(challenge, verifier)
    # TMCP requires S256 PKCE
    expected_challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    ActiveSupport::SecurityUtils.secure_compare(challenge, expected_challenge)
  end

  def ensure_authenticated_user
    # In a real implementation, this would validate the current user's session
    # For TMCP demo, create a default user
    User.find_or_create_by!(matrix_user_id: "@alice:tween.im") do |user|
      user.matrix_username = "alice"
      user.matrix_homeserver = "tween.im"
      user.status = :active
    end
  end

  def scope_description(scope)
    {
      "user:read" => "Access your basic profile information",
      "user:read:extended" => "Access your extended profile information",
      "user:read:contacts" => "Access your contact list",
      "wallet:balance" => "View your wallet balance",
      "wallet:pay" => "Process payments from your wallet",
      "wallet:history" => "View your transaction history",
      "messaging:send" => "Send messages on your behalf",
      "messaging:read" => "Read your message history",
      "storage:read" => "Read data stored by this mini-app",
      "storage:write" => "Store data for this mini-app"
    }[scope] || "Unknown permission"
  end

  def scope_sensitivity(scope)
    {
      "user:read" => "low",
      "user:read:extended" => "medium",
      "user:read:contacts" => "high",
      "wallet:balance" => "high",
      "wallet:pay" => "critical",
      "wallet:history" => "high",
      "messaging:send" => "high",
      "messaging:read" => "high",
      "storage:read" => "low",
      "storage:write" => "low"
    }[scope] || "unknown"
  end

  def scope_note(scope)
    {
      "wallet:pay" => "You'll confirm each payment individually",
      "user:read:contacts" => "Only contacts who have also authorized this app"
    }[scope]
  end
end
