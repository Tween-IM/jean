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

    def connect
      return redirect_to admin_login_path unless connection_staff?
      return redirect_to admin_dashboard_path, alert: "Tween ID sign-in is not configured." unless MasOidc.configured?
      pending = { "state" => MasOidc.new_state, "verifier" => MasOidc.new_code_verifier,
        "user_id" => current_admin_user.id, "started_at" => Time.current.to_i }
      session[:admin_connection] = pending
      redirect_to MasOidc.authorization_url(state: pending["state"], code_verifier: pending["verifier"],
        scope: AdminOauthGrant::REQUIRED_SCOPES.join(" ")), allow_other_host: true
    rescue MasOidc::Error
      redirect_to admin_dashboard_path, alert: "Could not start administration authorization. Please try again."
    end

    def create
      return complete_connection if session[:admin_connection]
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

      if Rails.env.production? && ENV.fetch("ADMIN_REQUIRE_MFA", "true") == "true" && !user.admin_mfa_enabled?
        return fail_login("Staff access requires an enrolled authenticator. Contact your administrator.")
      end
      AdminOauthGrant.disconnect(session.delete(:admin_oauth_key))
      reset_session
      if user.admin_mfa_enabled?
        session[:admin_mfa_pending_user_id] = user.id
        session[:admin_mfa_started_at] = Time.current.to_i
        return redirect_to admin_mfa_path
      end

      start_admin_session!(user)
      redirect_to admin_dashboard_path, notice: "Welcome, #{user.matrix_username || user.matrix_user_id}."
    rescue Admin::MasOidc::Error => e
      Rails.logger.error "[MAS_ADMIN_LOGIN] #{e.message}"
      fail_login("Tween ID sign-in failed. Please try again.")
    end

    private

    def connection_staff?
      user = current_admin_user
      return false unless user&.active? && user.platform_admin?
      return false unless user.has_admin_permission?(:view_messaging) || user.has_admin_permission?(:view_identity)
      last_activity = Time.iso8601(session[:admin_last_activity_at].to_s)
      last_activity > [ ENV.fetch("ADMIN_SESSION_TIMEOUT_MINUTES", 30).to_i, 5 ].max.minutes.ago
    rescue ArgumentError
      false
    end

    def complete_connection
      pending = session.delete(:admin_connection)
      tokens = nil
      installed = false
      unless connection_staff? && pending["user_id"] == current_admin_user.id
        return redirect_to admin_login_path, alert: "Your staff session changed or expired. Sign in again."
      end
      unless !stale?(pending["started_at"]) && params[:state].present? &&
          ActiveSupport::SecurityUtils.secure_compare(pending["state"].to_s, params[:state].to_s)
        return redirect_to admin_dashboard_path, alert: "That authorization expired or did not match. Please try again."
      end
      if params[:error].present? || params[:code].blank?
        return redirect_to admin_dashboard_path, alert: "Administration access was not granted. Your other workspace access is unchanged."
      end
      tokens = MasOidc.tokens_for(code: params[:code], code_verifier: pending["verifier"])
      claims = MasOidc.userinfo(tokens.fetch("access_token", ""))
      key = session[:admin_oauth_key].presence || SecureRandom.urlsafe_base64(32)
      AdminOauthGrant.transaction do
        AdminOauthGrant.install!(user: current_admin_user, key: key, subject: claims["sub"], tokens: tokens)
        AdminAuditEvent.create!(actor_matrix_id: current_admin_user.matrix_user_id,
          action: "connect_administration", target: claims["sub"], request_id: request.request_id)
      end
      session[:admin_oauth_key] = key
      installed = true
      redirect_to admin_resource_path("rooms"), notice: "Administration is connected using your own Tween ID."
    rescue MasOidc::Error, AdminOauthGrant::ConnectionRequired
      redirect_to admin_dashboard_path,
        alert: "Administration authorization failed. Use the Tween ID linked to your staff account; MAS must grant it admin access."
    ensure
      if tokens && !installed
        begin
          MasOidc.revoke(tokens["refresh_token"].presence || tokens["access_token"])
        rescue MasOidc::Error
          Rails.logger.warn("Could not revoke a rejected administration grant.")
        end
      end
    end

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
