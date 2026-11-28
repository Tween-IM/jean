module Admin
  class MiniAppsController < BaseController
    before_action -> { require_admin_permission!(:view_mini_apps) }, only: [ :index, :show, :bundle ]
    before_action :require_admin_permission!, only: [ :new, :create, :edit, :update, :destroy, :hard_delete, :activate, :website_preview ]
    before_action :set_mini_app, only: [ :show, :edit, :update, :destroy, :hard_delete, :bundle, :activate ]
    before_action :set_mini_app_for_edit, only: [ :new, :create ]

    rate_limit to: 6, within: 1.minute, only: :website_preview, by: -> { current_admin_user.id }, with: -> {
      render json: { error: "Too many preview requests. Try again in a minute." }, status: :too_many_requests
    }

    def website_preview
      url = PublicWebsiteFetch.url(params[:url])
      unless url
        render json: { error: "Use a public HTTPS URL without credentials." },
          status: :unprocessable_entity
        return
      end

      render json: MiniAppWebsitePreview.new.call(url)
    rescue PublicWebsiteFetch::Unavailable
      render json: {
        error: "This site blocks Tween’s server from reading it. Submit it from the Tween app so it can be read on your device, or fill the listing manually."
      }, status: :unprocessable_entity
    end

    def index
      scope = params[:sort] == 'name' ? MiniApp.order(name: :asc, id: :asc) : MiniApp.order(created_at: :desc, id: :desc)
      scope = scope.where(status: params[:status]) if MiniApp.statuses.key?(params[:status])
      if params[:query].present?
        pattern = "%#{MiniApp.sanitize_sql_like(params[:query].to_s.first(200))}%"
        scope = scope.where("name ILIKE :q OR app_id ILIKE :q OR developer_name ILIKE :q", q: pattern)
      end
      @mini_apps = paginate(scope)
      @archived_count = MiniApp.where(status: :removed).count
    end

    def new
      @mini_app = MiniApp.new(classification: :community, version: "1.0.0", manifest: { "scopes" => ["user:read"] })
    end

    def create
      @mini_app = MiniApp.new
      save_submission(:new)
    end

    def bundle
      return head :not_found unless @mini_app.bundle.attached?
      response.headers["Cache-Control"] = "private, no-store"
      response.headers["Content-Security-Policy"] = "sandbox; default-src 'none'"
      redirect_to rails_blob_path(@mini_app.bundle, disposition: "attachment")
    end

    def show
      @installation_page = paginate(@mini_app.miniapp_installations.includes(:user).order(created_at: :desc))
      @installations = @installation_page.records
      @automated_check = @mini_app.mini_app_automated_checks.order(created_at: :desc).first
      @appeals = @mini_app.mini_app_appeals.order(created_at: :desc).limit(10)
    end

    def edit
    end

    def update
      save_submission(:edit)
    end

    def activate
      return head :unprocessable_entity unless params[:reason].to_s.strip.length.between?(5, 1000)
      @mini_app.with_lock do
        return head :unprocessable_entity unless @mini_app.approved?
        @mini_app.activate!
        log_admin_action('activate_mini_app', @mini_app.app_id, reason: params[:reason])
      end
      redirect_to admin_mini_app_path(@mini_app), notice: 'Mini-app activated.'
    end

    def destroy
      return head :unprocessable_entity unless params[:reason].to_s.strip.length.between?(5, 1000)
      @mini_app.update!(status: :removed)
      log_admin_action("archive_mini_app", @mini_app.app_id, reason: params[:reason])
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

    def save_submission(template)
      Admin::MiniAppSubmission.call(app: @mini_app, attributes: mini_app_params,
        manifest: mini_app_manifest_params, upload: params.dig(:mini_app, :bundle))
      log_admin_action("submit_mini_app", @mini_app.app_id, version: @mini_app.version, delivery: @mini_app.bundle.attached? ? "bundle" : "hosted")
      redirect_to admin_mini_app_path(@mini_app), notice: "Mini-app saved to the review queue."
    rescue ActiveRecord::RecordInvalid, Admin::MiniAppSubmission::Invalid => error
      @mini_app.errors.add(:base, error.message)
      render template, status: :unprocessable_entity
    end

    def mini_app_manifest_params
      params.fetch(:manifest, ActionController::Parameters.new).permit(
        :entry_url, :icon_url, :header_image, :screenshots, :runtime, :webhook_url, :redirect_uris, permissions: []
      )
    end

    def mini_app_params
      params.require(:mini_app).permit(:name, :description, :classification, :version, :developer_name, :app_id, :client_type)
    end

    def require_admin_permission!(permission = :manage_mini_apps)
      super(permission)
    end
  end
end
