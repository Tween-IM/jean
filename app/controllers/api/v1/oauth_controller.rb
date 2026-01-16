class Api::V1::OauthController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [ :authorize, :token, :device_code, :device_token ]

  def authorize
    raw_params = params

    required_params = %w[response_type client_id redirect_uri scope state code_challenge code_challenge_method]
    missing_params = required_params.select { |param| raw_params[param].blank? }

    if missing_params.any?
      return render json: {
        error: "invalid_request",
        error_description: "Missing required parameters: #{missing_params.join(', ')}"
      }, status: :bad_request
    end

    unless raw_params[:response_type] == "code"
      return render json: { error: "unsupported_response_type" }, status: :bad_request
    end

    unless raw_params[:code_challenge_method] == "S256"
      return render json: {
        error: "invalid_request",
        error_description: "code_challenge_method must be S256"
      }, status: :bad_request
    end

    requested_scopes = raw_params[:scope].split
    valid_scopes = %w[user:read user:read:extended user:read:contacts wallet:balance wallet:pay wallet:history messaging:send messaging:read storage:read storage:write]
    invalid_scopes = requested_scopes - valid_scopes

    if invalid_scopes.any?
      return render json: {
        error: "invalid_scope",
        error_description: "Invalid scopes: #{invalid_scopes.join(', ')}"
      }, status: :bad_request
    end

    miniapp = MiniApp.find_by(app_id: raw_params[:client_id], status: :active)
    unless miniapp
      return render json: {
        error: "invalid_client",
        error_description: "Mini-app not found or inactive"
      }, status: :bad_request
    end

    auth_request_id = SecureRandom.urlsafe_base64(32)
    auth_request_data = {
      id: auth_request_id,
      client_id: raw_params[:client_id],
      redirect_uri: raw_params[:redirect_uri],
      scope: requested_scopes,
      state: raw_params[:state],
      code_challenge: raw_params[:code_challenge],
      code_challenge_method: raw_params[:code_challenge_method],
      miniapp_name: miniapp.name,
      miniapp_icon: nil,
      created_at: Time.current
    }
    Rails.cache.write("auth_request:#{auth_request_id}", auth_request_data, expires_in: 15.minutes)

    mas_auth_url = ENV["MAS_AUTH_URL"] || "https://auth.tween.example/oauth2/authorize"
    redirect_params = {
      client_id: raw_params[:client_id],
      redirect_uri: raw_params[:redirect_uri],
      response_type: "code",
      scope: raw_params[:scope],
      state: raw_params[:state],
      code_challenge: raw_params[:code_challenge],
      code_challenge_method: "S256"
    }

    redirect_to "#{mas_auth_url}?#{redirect_params.to_query}", allow_other_host: true
  end

  def device_code
    raw_params = params

    client_id = raw_params[:client_id]
    scope = raw_params[:scope] || "urn:matrix:org.matrix.msc2967.client:api:*"

    device_code = SecureRandom.urlsafe_base64(32)
    user_code = SecureRandom.alphanumeric(8).upcase.scan(/.{1,4}/).join("-")

    Rails.cache.write("device_code:#{device_code}", {
      client_id: client_id,
      scope: scope.split,
      user_code: user_code,
      created_at: Time.current
    }, expires_in: 15.minutes)

    render json: {
      device_code: device_code,
      user_code: user_code,
      verification_uri: "#{ENV["MAS_AUTH_URL"] || "https://auth.tween.example"}/device",
      expires_in: 900,
      interval: 5
    }
  end

  def device_token
    raw_params = params

    device_code = raw_params[:device_code]
    client_id = raw_params[:client_id]
    client_secret = raw_params[:client_secret]

    device_data = Rails.cache.read("device_code:#{device_code}")
    unless device_data
      return render json: { error: "authorization_pending" }, status: 400
    end

    mas_client = MasClientService.new(
      client_id: client_id,
      client_secret: client_secret,
      token_url: ENV["MAS_TOKEN_URL"] || "https://auth.tween.example/oauth2/token",
      introspection_url: ENV["MAS_INTROSPECTION_URL"] || "https://auth.tween.example/oauth2/introspect"
    )

    token_response = mas_client.client_credentials_grant

    render json: {
      access_token: token_response[:access_token],
      token_type: "Bearer",
      expires_in: token_response[:expires_in]
    }
  end

  def token
    raw_params = params

    grant_type = raw_params[:grant_type]
    Rails.logger.info "Received token request with grant_type: #{grant_type.inspect}"

    if grant_type == "urn:ietf:params:oauth:grant-type:token-exchange"
      handle_matrix_session_delegation(raw_params)
    elsif grant_type == "authorization_code"
      handle_authorization_code_flow(raw_params)
    elsif grant_type == "refresh_token"
      handle_refresh_token_flow(raw_params)
    else
      render json: { error: "unsupported_grant_type" }, status: :bad_request
    end
  end

  def consent
    session_id = params[:session]
    approved = params[:approved] == "true"

    consent_data = Rails.cache.read("consent:#{session_id}")
    unless consent_data
      return render json: {
        error: "invalid_request",
        error_description: "Invalid or expired consent session"
      }, status: :bad_request
    end

    if approved
      consent_data[:consent_required_scopes].each do |scope|
        AuthorizationApproval.create!(
          user_id: consent_data[:user_id],
          miniapp_id: consent_data[:miniapp_id],
          scope: scope,
          approved_at: Time.current,
          approval_method: "user_consent"
        )
      end
      Rails.cache.delete("consent:#{session_id}")

      render json: {
        message: "Consent recorded successfully"
      }, status: :ok
    else
      render json: {
        error: "consent_declined",
        error_description: "User declined consent"
      }, status: :bad_request
    end
  end

  private

  def handle_matrix_session_delegation(params)
    subject_token = params[:subject_token]
    subject_token_type = params[:subject_token_type]
    client_id = params[:client_id]
    client_secret = params[:client_secret]
    scopes = params[:scope] ? params[:scope].split : []
    miniapp_context = params[:miniapp_context] ? JSON.parse(params[:miniapp_context]) : {}

    unless subject_token && subject_token_type && client_id
      render json: {
        error: "invalid_request",
        error_description: "subject_token, subject_token_type and client_id are required"
      }, status: :bad_request
      return
    end

    unless subject_token_type == "urn:ietf:params:oauth:token-type:access_token"
      render json: {
        error: "invalid_request",
        error_description: "subject_token_type must be urn:ietf:params:oauth:token-type:access_token"
      }, status: :bad_request
      return
    end

    application = Doorkeeper::Application.find_by(uid: client_id)
    unless application
      render json: {
        error: "invalid_client",
        error_description: "Unknown client_id"
      }, status: :unauthorized
      return
    end

    miniapp = MiniApp.find_by(app_id: client_id)
    client_type = miniapp&.client_type || "public"

    if client_type == "confidential"
      client_secret = params[:client_secret]
      if client_secret.blank?
        render json: {
          error: "invalid_client",
          error_description: "client_secret is required for confidential clients"
        }, status: :unauthorized
        return
      end

      unless application.secret == client_secret
        render json: {
          error: "invalid_client",
          error_description: "Invalid client credentials"
        }, status: :unauthorized
        return
      end
    end

    mas_client = MasClientService.new(
      client_id: ENV["MAS_CLIENT_ID"] || "tmcp-server",
      client_secret: ENV["MAS_CLIENT_SECRET"],
      token_url: ENV["MAS_TOKEN_URL"] || "https://mas.tween.example/oauth2/token",
      introspection_url: ENV["MAS_INTROSPECTION_URL"] || "https://mas.tween.example/oauth2/introspect"
    )

    begin
      introspection_response = mas_client.introspect_token(subject_token)
      unless introspection_response["active"]
        render json: {
          error: "invalid_grant",
          error_description: "Subject token is not active"
        }, status: :bad_request
        return
      end

      matrix_user_id = introspection_response["sub"]
      unless matrix_user_id
        render json: {
          error: "invalid_grant",
          error_description: "Matrix token does not contain valid user ID"
        }, status: :bad_request
        return
      end

      user = User.find_or_create_by(matrix_user_id: matrix_user_id) do |u|
        username_homeserver = matrix_user_id.split("@").last
        localpart, domain = username_homeserver.split(":")
        u.matrix_username = localpart
        u.matrix_homeserver = domain
      end

      authorization_result = authorize_scopes(user, application, scopes)

      if authorization_result[:consent_required]
        render json: {
          error: "consent_required",
          error_description: "User must approve sensitive scopes",
          consent_required_scopes: authorization_result[:consent_required_scopes],
          pre_approved_scopes: authorization_result[:pre_approved_scopes],
          consent_ui_endpoint: "/oauth2/consent?session=#{authorization_result[:session_id]}"
        }, status: :forbidden
        return
      end

      tep_response = mas_client.exchange_matrix_token_for_tep(
        subject_token,
        client_id,
        authorization_result[:authorized_scopes],
        miniapp_context,
        introspection_response
      )

      render json: tep_response

    rescue MasClientService::InvalidTokenError, MasClientService::InvalidCredentialsError, MasClientService::MasError => e
      render json: {
        error: "invalid_grant",
        error_description: e.message
      }, status: :bad_request
    rescue JSON::ParserError
      render json: {
        error: "invalid_request",
        error_description: "Invalid miniapp_context JSON"
      }, status: :bad_request
    end
  end

  def handle_authorization_code_flow(params)
    auth_code = params[:code]
    auth_request_id = params[:state]
    matrix_access_token = params[:matrix_access_token]
    client_id = params[:client_id]

    auth_request = Rails.cache.read("auth_request:#{auth_request_id}")
    unless auth_request
      return render json: {
        error: "invalid_grant",
        error_description: "Authorization request not found"
      }, status: :bad_request
    end

    unless matrix_access_token
      return render json: {
        error: "invalid_request",
        error_description: "matrix_access_token is required"
      }, status: :bad_request
    end

    application = Doorkeeper::Application.find_by(uid: auth_request["client_id"])
    unless application
      return render json: {
        error: "invalid_client",
        error_description: "Unknown client_id"
      }, status: :unauthorized
    end

    mas_client = MasClientService.new(
      client_id: ENV["MAS_CLIENT_ID"] || "tmcp-server",
      client_secret: ENV["MAS_CLIENT_SECRET"],
      token_url: ENV["MAS_TOKEN_URL"] || "https://mas.tween.example/oauth2/token",
      introspection_url: ENV["MAS_INTROSPECTION_URL"] || "https://mas.tween.example/oauth2/introspect"
    )

    begin
      introspection_response = mas_client.introspect_token(matrix_access_token)
      unless introspection_response["active"]
        render json: {
          error: "invalid_grant",
          error_description: "Matrix token is not active"
        }, status: :bad_request
        return
      end

      matrix_user_id = introspection_response["sub"]
      unless matrix_user_id
        render json: {
          error: "invalid_grant",
          error_description: "Matrix token does not contain valid user ID"
        }, status: :bad_request
        return
      end

      user = User.find_or_create_by(matrix_user_id: matrix_user_id) do |u|
        username_homeserver = matrix_user_id.split("@").last
        localpart, domain = username_homeserver.split(":")
        u.matrix_username = localpart
        u.matrix_homeserver = domain
      end

      scopes = auth_request["scope"]
      tep_response = mas_client.exchange_matrix_token_for_tep(
        matrix_access_token,
        auth_request["client_id"],
        scopes,
        {},
        introspection_response
      )

      render json: tep_response

    rescue MasClientService::InvalidTokenError, MasClientService::MasError => e
      render json: {
        error: "invalid_grant",
        error_description: e.message
      }, status: :bad_request
    end
  end

  def handle_refresh_token_flow(params)
    refresh_token = params[:refresh_token]
    refresh_data = Rails.cache.read("refresh_token:#{refresh_token}")

    unless refresh_data
      render json: {
        error: "invalid_grant",
        error_description: "Refresh token expired or invalid"
       }, status: :bad_request
      return
    end

     user = User.find_by(matrix_user_id: refresh_data["user_id"])
     unless user
       render json: {
         error: "invalid_grant",
         error_description: "User not found"
       }, status: :bad_request
       return
     end

     access_token = TepTokenService.encode(
       {
         user_id: refresh_data["user_id"],
         miniapp_id: refresh_data["miniapp_id"]
       },
       scopes: refresh_data["scope"],
       wallet_id: user.wallet_id
     )

    new_refresh_token = SecureRandom.urlsafe_base64(32)
    Rails.cache.write("refresh_token:#{new_refresh_token}", refresh_data, expires_in: 30.days)

    render json: {
      access_token: access_token,
      token_type: "Bearer",
      expires_in: 86400,
      refresh_token: new_refresh_token,
      scope: refresh_data["scope"].join(" ")
    }
  end

  def authorize_scopes(user, application, requested_scopes)
    miniapp = MiniApp.find_by(app_id: application.uid)
    return { authorized_scopes: [], consent_required: false } unless miniapp

    sensitive_scopes = %w[wallet:pay wallet:request wallet:history messaging:send room:create room:invite]
    pre_approved_scopes = []
    consent_required_scopes = []

    requested_scopes.each do |scope|
      approved = AuthorizationApproval.where(
        user_id: user.matrix_user_id,
        miniapp_id: miniapp.app_id,
        scope: scope
      ).exists?

      if approved || !sensitive_scopes.include?(scope)
        pre_approved_scopes << scope
      else
        consent_required_scopes << scope
      end
    end

    if consent_required_scopes.any?
      session_id = SecureRandom.urlsafe_base64(32)
      Rails.cache.write("consent:#{session_id}", {
        user_id: user.matrix_user_id,
        miniapp_id: miniapp.app_id,
        pre_approved_scopes: pre_approved_scopes,
        consent_required_scopes: consent_required_scopes
      }, expires_in: 15.minutes)

      {
        authorized_scopes: [],
        consent_required: true,
        consent_required_scopes: consent_required_scopes,
        pre_approved_scopes: pre_approved_scopes,
        session_id: session_id
      }
    else
      {
        authorized_scopes: pre_approved_scopes,
        consent_required: false
      }
    end
  end
end
