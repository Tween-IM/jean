module Admin
  class UsersController < BaseController
    before_action -> { require_admin_permission!(:view_users) }, only: [ :index, :show ]
    before_action :require_manage_users!, only: [ :edit, :update ]
    before_action :set_user, only: [ :show, :edit, :update, :identity_command ]

    def index
      scope = User.order(created_at: :desc)
      if params[:query].present?
        pattern = "%#{User.sanitize_sql_like(params[:query].to_s.first(200))}%"
        scope = scope.where("matrix_user_id ILIKE :query OR matrix_username ILIKE :query", query: pattern)
      end
      scope = scope.where(status: params[:status]) if User.statuses.key?(params[:status])
      @users = paginate(scope)
    end

    def show
      @tabs = { "profile" => "Profile", "commerce" => "Commerce" }
      @tabs["apps"] = "Apps & access" if current_admin_user.has_admin_permission?(:view_mini_apps)
      @tabs["compliance"] = "Compliance" if current_admin_user.has_admin_permission?(:view_kyc)
      @tabs["payments"] = "Payments" if current_admin_user.has_admin_permission?(:view_wallets) || current_admin_user.has_admin_permission?(:view_transactions)
      @tabs["messaging"] = "Messaging" if current_admin_user.has_admin_permission?(:view_messaging)
      @tabs["identity"] = "Identity" if current_admin_user.has_admin_permission?(:view_identity)
      @tabs.delete("commerce") unless current_admin_user.has_admin_permission?(:view_orders)
      @tab = params[:tab].presence || "profile"
      return head :forbidden unless @tabs.key?(@tab)
      case @tab
      when "compliance" then @remote = TweenPay::AdminClient.new(current_admin_user).person(@user.matrix_user_id)
      when "payments" then @remote = TweenPay::AdminClient.new(current_admin_user).person(@user.matrix_user_id)
      when "messaging" then @remote = SynapseClient.new(grant: admin_oauth_grant).person(@user.matrix_user_id)
      when "identity" then @remote = MasClient.new(grant: admin_oauth_grant).person(@user.mas_user_id)
      when "apps"
        @installations = @user.miniapp_installations.includes(:mini_app).order(created_at: :desc).limit(20)
        @mfa_methods = @user.mfa_methods
        @storage_entries = @user.storage_entries.order(created_at: :desc).limit(10) if current_admin_user.has_admin_permission?(:view_storage)
      when "commerce"
        @orders = CommerceOrder.where(buyer_user_id: @user.matrix_user_id).order(created_at: :desc).limit(20)
      end
    rescue RemoteClient::Unavailable, RemoteClient::Forbidden, RemoteClient::NotFound, RemoteClient::Rejected => e
      @needs_authorization = e.is_a?(AdminOauthGrant::ConnectionRequired)
      @remote_error = e.message
    end

    def identity_command
      return head :forbidden unless current_admin_user.has_admin_permission?(:manage_identity)
      return head :unprocessable_entity unless %w[lock unlock].include?(params[:operation]) &&
        params[:reason].to_s.strip.length.between?(5, 1000) && @user.mas_user_id.present?
      event = AdminAuditEvent.create!(actor_matrix_id: current_admin_user.matrix_user_id,
        action: "identity.#{params[:operation]}", target: @user.mas_user_id, request_id: request.request_id,
        outcome: "pending", details: { reason: params[:reason] })
      MasClient.new(grant: admin_oauth_grant).account_action(@user.mas_user_id, params[:operation])
      event.update!(outcome: "success")
      redirect_to admin_user_path(@user, tab: "identity"), notice: "Identity account updated."
    rescue RemoteClient::Unavailable, RemoteClient::Forbidden, RemoteClient::NotFound, RemoteClient::Rejected => e
      event&.update!(outcome: e.is_a?(RemoteClient::Unavailable) ? "unknown" : "failed")
      redirect_to admin_user_path(@user, tab: "identity"), alert: e.message
    end

    def edit
    end

    def update
      if @user.update(user_params)
        log_admin_action("update_user", @user.matrix_user_id, params.to_unsafe_h)
        redirect_to admin_user_path(@user), notice: "User updated successfully."
      else
        flash.now[:alert] = "Failed to update user: #{@user.errors.full_messages.join(', ')}"
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_user
      @user = User.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_users_path, alert: "User not found."
    end

    def user_params
      params.require(:user).permit(:status, :platform_role)
    end

    def require_manage_users!
      require_admin_permission!(:manage_users)
    end
  end
end
