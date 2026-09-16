# frozen_string_literal: true

module Admin
  # Staff sign-in through Tween ID (the Matrix Authentication Service).
  #
  # Nothing here authenticates a password: MAS does that, and this controller
  # only verifies where the browser came back from, exchanges the code, and
  # checks that the identity jean knows is a platform admin. Accounts are
  # created in MAS; jean only grants `platform_role`.
  #
  # `Admin::SessionsController` stays available as the break-glass path (and
  # for environments where MAS is not configured).
  class MasSessionsController < ActionController::Base
    layout "admin"

    # A stale round-trip (user wandered off, another tab finished) should fail
    # closed rather than let a code be replayed.
    STATE_TTL = 10.minutes

    def new
      return redirect_to admin_dashboard_path if current_admin_user&.platform_admin?

      unless Admin::MasOidc.configured?
        return redirect_to admin_login_path,
          alert: "Tween ID sign-in is not configured on this server. Use the admin token form instead."
      end

      state = Admin::MasOidc.new_state
      verifier = Admin::MasOidc.new_code_verifier
      session[:admin_mas_state] = state
      session[:admin_mas_verifier] = verifier
      session[:admin_mas_started_at] = Time.current.to_i

      redirect_to Admin::MasOidc.authorization_url(state: state, code_verifier: verifier), allow_other_host: true
    rescue Admin::MasOidc::Error => e
      Rails.logger.error "[MAS_ADMIN_LOGIN] #{e.message}"
      redirect_to admin_login_path, alert: "Could not start Tween ID sign-in. Please try again."
    end

    def create
      state = session.delete(:admin_mas_state)
      verifier = session.delete(:admin_mas_verifier)
      started_at = session.delete(:admin_mas_started_at)

      return fail_login("Sign-in was cancelled.") if params[:error].present?
      return fail_login("That sign-in request has already been used or expired. Please try again.") if state.blank?
      return fail_login("Sign-in took too long. Please try again.") if stale?(started_at)
      return fail_login("Sign-in request did not match. Please try again.") unless valid_state?(state)
      return fail_login("Sign-in code was missing. Please try again.") if params[:code].blank?

      claims = Admin::MasOidc.claims_for(code: params[:code], code_verifier: verifier)
      user = Admin::MasOidc.user_for(claims)

      return fail_login("No platform account is linked to that Tween ID.") if user.nil?
      return fail_login("That Tween ID is not a platform admin.") unless user.platform_admin?
      return fail_login("That account is not active.") unless user.active?

      Rails.logger.info "[MAS_ADMIN_LOGIN] user=#{user.id} matrix_user_id=#{user.matrix_user_id}"

      if user.admin_mfa_enabled?
        session[:admin_mfa_pending_user_id] = user.id
        return redirect_to admin_mfa_path
      end

      start_admin_session!(user)
      redirect_to admin_dashboard_path, notice: "Welcome, #{user.matrix_username || user.matrix_user_id}."
    rescue Admin::MasOidc::Error => e
      Rails.logger.error "[MAS_ADMIN_LOGIN] #{e.message}"
      fail_login("Tween ID sign-in failed. Please try again.")
    end

    private

    def stale?(started_at)
      started_at.blank? || Time.at(started_at.to_i) < STATE_TTL.ago
    rescue ArgumentError, TypeError
      true
    end

    def valid_state?(expected)
      provided = params[:state].to_s
      provided.present? && ActiveSupport::SecurityUtils.secure_compare(expected, provided)
    end

    def start_admin_session!(user)
      session[:admin_user_id] = user.id
      session[:admin_last_activity_at] = Time.current.iso8601
      session[:admin_mfa_verified] = true
    end

    def fail_login(message)
      redirect_to admin_login_path, alert: message
    end

    def current_admin_user
      @current_admin_user ||= User.find_by(id: session[:admin_user_id])
    end
  end
end
