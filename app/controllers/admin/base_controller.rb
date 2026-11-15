module Admin
  class BaseController < ActionController::Base
    include Admin::Pagination

    layout -> { turbo_frame_request? && request.headers["Turbo-Frame"] == "admin-detail" ? "admin_drawer" : "admin" }
    protect_from_forgery with: :exception

    before_action :authenticate_admin!
    before_action :check_admin_session_timeout!

    helper_method :current_admin_user

    private

    def authenticate_admin!
      unless current_admin_user&.platform_admin? && current_admin_user.active?
        reset_admin_session!
        redirect_to admin_login_path
      end
    end

    def current_admin_user
      return @current_admin_user if defined?(@current_admin_user)
      @current_admin_user = User.find_by(id: session[:admin_user_id])
    end

    def check_admin_session_timeout!
      unless session[:admin_last_activity_at]
        reset_admin_session!
        return redirect_to admin_login_path
      end
      timeout = [ ENV.fetch("ADMIN_SESSION_TIMEOUT_MINUTES", 30).to_i, 5 ].max.minutes
      if Time.iso8601(session[:admin_last_activity_at]) < timeout.ago
        reset_admin_session!
        redirect_to admin_login_path, alert: "Your session has expired. Please sign in again."
      else
        session[:admin_last_activity_at] = Time.current.iso8601
      end
    rescue ArgumentError
      reset_admin_session!
      redirect_to admin_login_path, alert: "Your session has expired. Please sign in again."
    end

    def require_admin_permission!(permission)
      unless current_admin_user&.has_admin_permission?(permission)
        redirect_to admin_dashboard_path, alert: "You are not authorized to perform this action."
      end
    end

    def admin_oauth_grant
      AdminOauthGrant.for_session(current_admin_user, session[:admin_oauth_key])
    end

    def reset_admin_session!
      AdminOauthGrant.disconnect(session.delete(:admin_oauth_key))
      session.delete(:admin_user_id)
      session.delete(:admin_last_activity_at)
      session.delete(:admin_mfa_verified)
      session.delete(:admin_mfa_pending_user_id)
      session.delete(:admin_mfa_started_at)
      session.delete(:admin_mas_state)
      session.delete(:admin_mas_verifier)
      session.delete(:admin_mas_started_at)
    end

    def log_admin_action(action, resource = nil, details = {})
      AdminAuditEvent.create!(actor_matrix_id: current_admin_user.matrix_user_id,
        action: action, target: resource.to_s, request_id: request.request_id,
        details: AdminAuditEvent.safe_details(details))
    end
  end
end
