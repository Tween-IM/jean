module Admin
  class SessionsController < ActionController::Base
    layout "admin"

    def new
      redirect_to admin_dashboard_path if current_admin_user&.platform_admin?
    end

    def create
      user = User.find_by(matrix_user_id: params[:matrix_user_id]&.strip)

      if user.nil? || !user.platform_admin?
        flash.now[:alert] = "Invalid credentials or insufficient privileges."
        render :new, status: :unprocessable_entity
        return
      end

      # Check MFA if enabled
      if user.admin_mfa_enabled?
        if params[:mfa_code].blank?
          session[:admin_mfa_pending_user_id] = user.id
          render :mfa, status: :ok
          return
        end

        unless verify_admin_mfa!(user, params[:mfa_code])
          flash.now[:alert] = "Invalid MFA code. Please try again."
          render :mfa, status: :unprocessable_entity
          return
        end

        session[:admin_mfa_verified] = true
      end

      session[:admin_user_id] = user.id
      session[:admin_last_activity_at] = Time.current.iso8601
      redirect_to admin_dashboard_path, notice: "Welcome, #{user.matrix_username || user.matrix_user_id}."
    end

    def mfa
      unless session[:admin_mfa_pending_user_id]
        redirect_to admin_login_path
      end
    end

    def verify_mfa
      user = User.find_by(id: session[:admin_mfa_pending_user_id])

      unless user && verify_admin_mfa!(user, params[:mfa_code])
        flash.now[:alert] = "Invalid MFA code. Please try again."
        render :mfa, status: :unprocessable_entity
        return
      end

      session.delete(:admin_mfa_pending_user_id)
      session[:admin_user_id] = user.id
      session[:admin_last_activity_at] = Time.current.iso8601
      session[:admin_mfa_verified] = true
      redirect_to admin_dashboard_path, notice: "Welcome, #{user.matrix_username || user.matrix_user_id}."
    end

    def destroy
      reset_admin_session!
      redirect_to admin_login_path, notice: "You have been signed out."
    end

    helper_method :current_admin_user

    private

    def current_admin_user
      @current_admin_user ||= User.find_by(id: session[:admin_user_id])
    end

    def reset_admin_session!
      session.delete(:admin_user_id)
      session.delete(:admin_last_activity_at)
      session.delete(:admin_mfa_verified)
      session.delete(:admin_mfa_pending_user_id)
    end

    def verify_admin_mfa!(user, code)
      return false if user.admin_mfa_secret.blank?
      require "rotp"
      ROTP::TOTP.new(user.admin_mfa_secret).verify(code.strip, drift_behind: 30, drift_ahead: 30)
    rescue LoadError
      Rails.logger.error "ROTP gem not available for MFA verification"
      false
    end
  end
end
