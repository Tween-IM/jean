module Admin
  class UsersController < BaseController
    before_action :require_admin_permission!, only: [:edit, :update]
    before_action :set_user, only: [:show, :edit, :update]

    def index
      @users = paginate(User.order(created_at: :desc))
    end

    def show
      @installations = @user.miniapp_installations.includes(:mini_app).order(created_at: :desc).limit(20)
      @storage_entries = @user.storage_entries.order(created_at: :desc).limit(10)
      @mfa_methods = @user.mfa_methods
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

    def require_admin_permission!
      super(:manage_users)
    end
  end
end
