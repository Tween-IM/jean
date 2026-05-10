module Admin
  class MiniAppsController < BaseController
    before_action :require_admin_permission!, only: [:edit, :update, :destroy]
    before_action :set_mini_app, only: [:show, :edit, :update, :destroy]

    def index
      @mini_apps = paginate(MiniApp.order(created_at: :desc))
    end

    def show
      @installations = @mini_app.miniapp_installations.includes(:user).order(created_at: :desc).limit(20)
      @automated_check = @mini_app.mini_app_automated_checks.order(created_at: :desc).first
      @appeals = @mini_app.mini_app_appeals.order(created_at: :desc).limit(10)
    end

    def edit
    end

    def update
      if @mini_app.update(mini_app_params)
        log_admin_action("update_mini_app", @mini_app.app_id, params.to_unsafe_h)
        redirect_to admin_mini_app_path(@mini_app), notice: "Mini-app updated successfully."
      else
        flash.now[:alert] = "Failed to update mini-app: #{@mini_app.errors.full_messages.join(', ')}"
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @mini_app.destroy!
      log_admin_action("destroy_mini_app", @mini_app.app_id)
      redirect_to admin_mini_apps_path, notice: "Mini-app deleted successfully."
    rescue ActiveRecord::RecordNotDestroyed => e
      redirect_to admin_mini_apps_path, alert: "Failed to delete mini-app: #{e.message}"
    end

    private

    def set_mini_app
      @mini_app = MiniApp.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_mini_apps_path, alert: "Mini-app not found."
    end

    def mini_app_params
      params.require(:mini_app).permit(:name, :description, :status, :classification, :version, :developer_name)
    end

    def require_admin_permission!
      super(:manage_mini_apps)
    end
  end
end
