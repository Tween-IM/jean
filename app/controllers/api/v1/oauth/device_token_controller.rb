class Api::V1::Oauth::DeviceTokenController < ApplicationController
  def create
    grant_type = params[:grant_type]

    unless grant_type == "urn:ietf:params:oauth:grant-type:device_code"
      render json: {
        error: "unsupported_grant_type",
        error_description: "Only device_code grant is supported at this endpoint"
      }, status: :bad_request
      return
    end

    device_code = params[:device_code]
    client_id = params[:client_id]
    client_secret = params[:client_secret]

    device_auth = Rails.cache.read("device_auth:#{device_code}")

    unless device_auth
      render json: {
        error: "invalid_grant",
        error_description: "Invalid or expired device_code"
      }, status: :bad_request
      return
    end

    unless device_auth[:client_id] == client_id
      render json: {
        error: "invalid_grant",
        error_description: "Client ID mismatch"
      }, status: :bad_request
      return
    end

    application = Doorkeeper::Application.find_by(uid: client_id)
    unless application && application.secret == client_secret
      render json: {
        error: "invalid_client",
        error_description: "Invalid client credentials"
      }, status: :unauthorized
      return
    end

    user_id = authenticate_user_with_mas

    unless user_id
      render json: {
        error: "authorization_pending",
        error_description: "User has not completed authorization"
      }, status: :bad_request
      return
    end

    user = User.find_by(matrix_user_id: user_id)
    unless user
      render json: {
        error: "invalid_grant",
        error_description: "User not found"
      }, status: :bad_request
      return
    end

    scopes = device_auth[:scopes]
    miniapp_context = device_auth[:miniapp_context] || {}

    tep_response = exchange_for_tep_token(user, application, scopes, miniapp_context)

    render json: tep_response, status: :ok
  end

  private

  def authenticate_user_with_mas
    mock_user_id = params[:user_id] || "mock_user_#{SecureRandom.alphanumeric(8)}"

    if Rails.env.development? || Rails.env.test?
      return mock_user_id
    end

    mas_client = MasClientService.new
    mas_client.get_user_info(params[:matrix_access_token])["sub"]
  rescue MasClientService::MasError, MasClientService::InvalidTokenError
    nil
  end

  def exchange_for_tep_token(user, application, scopes, miniapp_context)
    mas_client = MasClientService.new
    mas_client.exchange_matrix_token_for_tep(
      params[:matrix_access_token] || "mock_matrix_token",
      application.uid,
      scopes,
      miniapp_context
    )
  end
end
