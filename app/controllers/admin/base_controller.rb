module Admin
  class BaseController < ActionController::Base
    include Admin::Pagination

    layout "admin"
    protect_from_forgery with: :exception

    before_action :authenticate_admin!
    before_action :check_admin_session_timeout!

    helper_method :current_admin_user

    private

    def authenticate_admin!
      redirect_to admin_login_path unless current_admin_user&.platform_admin?
    end

    def current_admin_user
      return @current_admin_user if defined?(@current_admin_user)
      @current_admin_user = User.find_by(id: session[:admin_user_id])
    end

    def check_admin_session_timeout!
      return unless session[:admin_last_activity_at]
      timeout = ENV.fetch("ADMIN_SESSION_TIMEOUT_MINUTES", 30).to_i.minutes
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

    def reset_admin_session!
      session.delete(:admin_user_id)
      session.delete(:admin_last_activity_at)
      session.delete(:admin_mfa_verified)
    end

    def log_admin_action(action, resource = nil, details = {})
      Rails.logger.info "[ADMIN_AUDIT] user=#{current_admin_user&.id} action=#{action} resource=#{resource} details=#{sanitize_audit_details(details).to_json}"
    rescue => e
      Rails.logger.error "[ADMIN_AUDIT_FAILED] #{e.message}"
    end

    def sanitize_audit_details(details)
      forbidden = %w[password secret token mfa_secret pin credit_card ssn]
      details.deep_stringify_keys.except(*forbidden)
    end
  end
end
