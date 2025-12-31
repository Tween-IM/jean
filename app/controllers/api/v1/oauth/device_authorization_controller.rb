class Api::V1::Oauth::DeviceAuthorizationController < ApplicationController
  before_action :validate_client_id

  ALLOWED_ALGORITHMS = %w[RS256 RS384 RS512].freeze

  def create
    device_code = generate_device_code
    user_code = generate_user_code

    device_auth = {
      device_code: device_code,
      user_code: user_code,
      verification_uri: verification_uri,
      verification_uri_complete: "#{verification_uri}?user_code=#{user_code}",
      expires_in: 900,
      interval: 5
    }

    Rails.cache.write("device_auth:#{device_code}", {
      device_code: device_code,
      user_code: user_code,
      client_id: params[:client_id],
      scopes: requested_scopes,
      miniapp_context: miniapp_context,
      created_at: Time.current.to_i
    }, expires_in: 15.minutes)

    render json: device_auth, status: :ok
  end

  def show
    user_code = params[:user_code]

    device_auth = find_device_auth_by_user_code(user_code)

    unless device_auth
      return render json: {
        error: "authorization_pending",
        error_description: "Device authorization is still pending"
      }, status: :bad_request
    end

    if Time.current.to_i - device_auth[:created_at] > 900
      Rails.cache.delete("device_auth:#{device_auth[:device_code]}")
      return render json: {
        error: "expired_token",
        error_description: "Device authorization has expired"
      }, status: :bad_request
    end

    render json: {
      user_code: user_code,
      status: "pending"
    }, status: :ok
  end

  private

  def validate_client_id
    client_id = params[:client_id]
    application = Doorkeeper::Application.find_by(uid: client_id)

    unless application
      render json: {
        error: "invalid_client",
        error_description: "Unknown client_id"
      }, status: :unauthorized
    end
  end

  def requested_scopes
    scope_param = params[:scope] || ""
    scope_param.split.select { |s| valid_scope?(s) }
  end

  def valid_scope?(scope)
    valid_tmcp_scopes.include?(scope) || valid_matrix_scopes.include?(scope)
  end

  def valid_tmcp_scopes
    %w[
      user:read user:read:extended user:read:contacts
      wallet:balance wallet:pay wallet:history wallet:request
      messaging:send messaging:read
      storage:read storage:write webhook:send
      room:create room:invite
    ]
  end

  def valid_matrix_scopes
    %w[
      openid
      urn:matrix:org.matrix.msc2967.client:api:*
      urn:matrix:org.matrix.msc2967.client:device:*
    ]
  end

  def miniapp_context
    context_param = params[:miniapp_context]
    return {} unless context_param.present?

    JSON.parse(context_param)
  rescue JSON::ParserError
    {}
  end

  def verification_uri
    "#{request.protocol}#{request.host_with_port}/oauth2/device"
  end

  def generate_device_code
    SecureRandom.urlsafe_base64(32).gsub(/[-_]/, "")
  end

  def generate_user_code
    chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    Array.new(8) { chars[rand(chars.length)] }.join
  end

  def find_device_auth_by_user_code(user_code)
    cache_keys = Rails.cache.instance_variable_get(:@data)&.keys || []
    cache_keys.each do |key|
      if key.start_with?("device_auth:")
        auth = Rails.cache.read(key)
        next unless auth
        if auth[:user_code] == user_code
          return auth
        end
      end
    end
    nil
  end
end
