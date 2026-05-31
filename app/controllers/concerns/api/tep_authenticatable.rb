module Api::TepAuthenticatable
  extend ActiveSupport::Concern

  class InsufficientScopeError < StandardError
    attr_reader :missing_scopes

    def initialize(missing_scopes)
      @missing_scopes = missing_scopes
      super("#{missing_scopes.join(', ')} scope required")
    end
  end

  included do
    rescue_from InsufficientScopeError, with: :render_insufficient_scope
  end

  private

    def authenticate_tep_token
      auth_header = request.headers["Authorization"]
      Rails.logger.info "[TEP_AUTH] Authorization header present: #{auth_header.present?} | path: #{request.path}"

      if auth_header.blank? || !auth_header.start_with?("Bearer ")
        Rails.logger.warn "[TEP_AUTH] Missing or malformed Authorization header"
        return render json: { error: "missing_token", message: "TEP token required" }, status: :unauthorized
      end

      @tep_token = auth_header.delete_prefix("Bearer ").strip
      Rails.logger.info "[TEP_AUTH] Token prefix: #{@tep_token[0..20]}... | length: #{@tep_token.length}"

      payload = TepTokenService.decode(@tep_token)
      Rails.logger.info "[TEP_AUTH] Token decoded — sub: #{payload["sub"]}, aud: #{payload["aud"]}, exp: #{Time.at(payload["exp"])}"

      @current_user = User.find_by(matrix_user_id: payload["sub"])
      unless @current_user
        Rails.logger.warn "[TEP_AUTH] User not found for sub: #{payload["sub"]}"
        return render json: { error: "invalid_token", message: "User not found" }, status: :unauthorized
      end

      Rails.logger.info "[TEP_AUTH] Authenticated user: #{@current_user.matrix_user_id}"
      @miniapp_id = payload["aud"]
      @token_scopes = payload["scope"].to_s.split
    rescue JWT::DecodeError => e
      Rails.logger.error "[TEP_AUTH] JWT decode failed: #{e.class} — #{e.message}"
      render json: { error: "invalid_token", message: e.message }, status: :unauthorized
    end

    def require_scope(*scopes)
      # First-party apps have wildcard permission — skip scope checks
      first_party_apps = ENV.fetch("FIRST_PARTY_MINIAPPS", "ma_tweenpay,ma_tweencommerce,ma_tweensocial").split(",")
      return if first_party_apps.include?(@miniapp_id)

      missing_scopes = scopes.flatten - @token_scopes
      return if missing_scopes.empty?

      raise InsufficientScopeError, missing_scopes
    end

    def render_insufficient_scope(error)
      render json: {
        error: "insufficient_scope",
        message: error.message
      }, status: :forbidden
    end
end
