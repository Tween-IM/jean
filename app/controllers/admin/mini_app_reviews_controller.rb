module Admin
  class MiniAppReviewsController < BaseController
    before_action :set_mini_app, only: [:show, :approve, :reject, :request_changes]

    def index
      @pending_apps = MiniApp.under_review.order(submitted_at: :asc)
      @appeals = MiniApp.appeal_submitted.order(created_at: :asc)
    end

    def show
      @automated_check = @mini_app.latest_automated_check
      @appeals = @mini_app.mini_app_appeals.order(created_at: :desc)
      @installations = @mini_app.miniapp_installations.includes(:user).order(created_at: :desc).limit(20)
    end

    def approve
      @mini_app.approve!(reviewer_id: current_admin_user.id)

      redirect_to admin_mini_app_reviews_path, notice: "#{@mini_app.name} has been approved."
    rescue => e
      redirect_to admin_mini_app_reviews_path, alert: "Failed to approve: #{e.message}"
    end

    def reject
      @mini_app.reject!(
        reviewer_id: current_admin_user.id,
        reason: params[:reason] || "Application does not meet guidelines."
      )

      redirect_to admin_mini_app_reviews_path, notice: "#{@mini_app.name} has been rejected."
    rescue => e
      redirect_to admin_mini_app_reviews_path, alert: "Failed to reject: #{e.message}"
    end

    def request_changes
      @mini_app.request_changes!(
        reviewer_id: current_admin_user.id,
        reason: params[:reason] || "Please review the application and make necessary changes."
      )

      redirect_to admin_mini_app_reviews_path, notice: "#{@mini_app.name} returned to developer with revision request."
    rescue => e
      redirect_to admin_mini_app_reviews_path, alert: "Failed to request changes: #{e.message}"
    end

    def resolve_appeal
      appeal = MiniAppAppeal.find(params[:appeal_id])

      if params[:approve]
        mini_app = appeal.miniapp
        mini_app.approve!(reviewer_id: current_admin_user.id)
        appeal.update!(status: :approved)
      else
        mini_app = appeal.miniapp
        mini_app.update!(status: :rejected)
        appeal.update!(status: :rejected, supporting_info: "Appeal denied: #{params[:reason]}")
      end

      redirect_to admin_mini_app_reviews_path, notice: "Appeal resolved."
    rescue => e
      redirect_to admin_mini_app_reviews_path, alert: "Failed to resolve appeal: #{e.message}"
    end

    private

    def set_mini_app
      @mini_app = MiniApp.find(params[:id] || params[:mini_app_id])
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_mini_app_reviews_path, alert: "Mini-app not found."
    end
  end
end