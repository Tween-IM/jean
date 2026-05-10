module Admin
  class OauthApplicationsController < BaseController
    before_action :require_admin_permission!, only: [:destroy]
    before_action :set_application, only: [:show, :destroy]

    def index
      @applications = paginate(Doorkeeper::Application.order(created_at: :desc))
    end

    def show
      @access_tokens = Doorkeeper::AccessToken.where(application_id: @application.id).order(created_at: :desc).limit(20)
      @access_grants = Doorkeeper::AccessGrant.where(application_id: @application.id).order(created_at: :desc).limit(20)
    end

    def destroy
      @application.destroy!
      log_admin_action("destroy_oauth_app", @application.uid)
      redirect_to admin_oauth_applications_path, notice: "OAuth application deleted successfully."
    rescue ActiveRecord::RecordNotDestroyed => e
      redirect_to admin_oauth_applications_path, alert: "Failed to delete OAuth application: #{e.message}"
    end

    private

    def set_application
      @application = Doorkeeper::Application.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_oauth_applications_path, alert: "OAuth application not found."
    end

    def require_admin_permission!
      super(:manage_oauth)
    end
  end
end
