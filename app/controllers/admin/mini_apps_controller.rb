module Admin
  class MiniAppsController < BaseController
    before_action :require_admin_permission!, only: [:new, :create, :edit, :update, :destroy, :hard_delete]
    before_action :set_mini_app, only: [:show, :edit, :update, :destroy, :hard_delete]
    before_action :set_mini_app_for_edit, only: [:new, :create]

    def index
      @mini_apps = paginate(MiniApp.order(created_at: :desc))
      @archived_count = MiniApp.where(status: :removed).count
    end

    def new
      @mini_app = MiniApp.new
    end

    def create
      @mini_app = MiniApp.new(mini_app_params)

      if @mini_app.save
        log_admin_action("create_mini_app", @mini_app.app_id, params.to_unsafe_h)
        redirect_to admin_mini_app_path(@mini_app), notice: "Mini-app created successfully."
      else
        flash.now[:alert] = "Failed to create mini-app: #{@mini_app.errors.full_messages.join(', ')}"
        render :new, status: :unprocessable_entity
      end
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
      @mini_app.update!(status: :removed)
      log_admin_action("archive_mini_app", @mini_app.app_id)
      redirect_to admin_mini_apps_path, notice: "Mini-app has been archived."
    rescue => e
      redirect_to admin_mini_apps_path, alert: "Failed to archive mini-app: #{e.message}"
    end

    def hard_delete
      app_id = @mini_app.app_id
      app_name = @mini_app.name
      @mini_app.destroy!
      log_admin_action("hard_delete_mini_app", app_id)
      redirect_to admin_mini_apps_path, notice: "Mini-app '#{app_name}' has been permanently deleted."
    rescue ActiveRecord::RecordNotDestroyed => e
      redirect_to admin_mini_app_path(@mini_app), alert: "Failed to delete mini-app: #{e.message}"
    end

    private

    def set_mini_app
      @mini_app = MiniApp.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_mini_apps_path, alert: "Mini-app not found."
    end

    def set_mini_app_for_edit
      @mini_app = MiniApp.new
    end

    def mini_app_params
      permitted = params.require(:mini_app).permit(:name, :description, :status, :classification, :version, :developer_name, :app_id)

      will_be_official = params[:mini_app][:classification] == "official" || @mini_app.classification == "official"
      manifest_data = params[:manifest]

      if manifest_data.present? && will_be_official
        manifest = {}
        manifest["entry_url"] = params[:manifest][:entry_url] if params[:manifest][:entry_url].present?
        manifest["icon_url"] = params[:manifest][:icon_url] if params[:manifest][:icon_url].present?
        manifest["webhook_url"] = params[:manifest][:webhook_url] if params[:manifest][:webhook_url].present?

        if params[:manifest][:redirect_uris].present?
          manifest["redirect_uris"] = params[:manifest][:redirect_uris].split("\n").map(&:strip).reject(&:empty?)
        end

        scopes = params[:manifest][:permissions]
        manifest["scopes"] = scopes.is_a?(Array) ? scopes : [scopes].compact

        permitted = permitted.merge(manifest: manifest)
      end

      permitted
    end

    def require_admin_permission!
      super(:manage_mini_apps)
    end
  end
end
