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
      return render json: { error: "missing_token", message: "TEP token required" }, status: :unauthorized unless auth_header&.start_with?("Bearer ")

      @tep_token = auth_header.delete_prefix("Bearer ")
      payload = TepTokenService.decode(@tep_token)

      @current_user = User.find_by(matrix_user_id: payload["sub"])
      return render json: { error: "invalid_token", message: "User not found" }, status: :unauthorized unless @current_user

      @miniapp_id = payload["aud"]
      @token_scopes = payload["scope"].to_s.split
    rescue JWT::DecodeError => e
      render json: { error: "invalid_token", message: e.message }, status: :unauthorized
    end

    def require_scope(*scopes)
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
