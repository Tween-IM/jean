module Admin
  class MiniAppReviewsController < BaseController
    before_action -> { require_admin_permission!(:view_mini_apps) }, only: [ :index, :show ]
    before_action -> { require_admin_permission!(:manage_mini_apps) }, except: [ :index, :show ]
    before_action :set_mini_app, only: [ :show, :approve, :reject, :request_changes ]
    before_action :validate_decision!, only: [:approve, :reject, :request_changes]

    def index
      @queue = params[:queue] == 'appeals' ? 'appeals' : 'reviews'
      scope = MiniApp.where(status: @queue == 'appeals' ? :appeal_submitted : [:pending_review, :under_review]).order(:created_at)
      @review_page = paginate(scope)
      @pending_apps = @queue == 'reviews' ? @review_page.records : []
      @appeals = @queue == 'appeals' ? @review_page.records : []
    end

    def show
      @automated_check = @mini_app.latest_automated_check
      @appeals = @mini_app.mini_app_appeals.order(created_at: :desc)
      @installations = @mini_app.miniapp_installations.includes(:user).order(created_at: :desc).limit(20)
    end

    def approve
      review_submission('approve_mini_app') { @mini_app.approve!(reviewer_id: current_admin_user.id) }
    end

    def reject
      review_submission('reject_mini_app') { @mini_app.reject!(reviewer_id: current_admin_user.id, reason: params[:reason]) }
    end

    def request_changes
      review_submission('request_mini_app_changes') { @mini_app.request_changes!(reviewer_id: current_admin_user.id, reason: params[:reason]) }
    end

    def resolve_appeal
      return head :unprocessable_entity unless params[:reason].to_s.strip.length.between?(5, 1000)
      appeal = MiniAppAppeal.find(params[:appeal_id])
      approved = ActiveModel::Type::Boolean.new.cast(params[:approve])
      appeal.with_lock do
        return head :unprocessable_entity unless appeal.status == 'pending_review' && appeal.miniapp
        appeal.miniapp.with_lock do
          return head :unprocessable_entity unless %w[appeal_submitted rejected].include?(appeal.miniapp.status)
          if approved
            appeal.miniapp.approve!(reviewer_id: current_admin_user.id)
          else
            appeal.miniapp.reject!(reviewer_id: current_admin_user.id, reason: params[:reason])
          end
          appeal.update!(status: approved ? 'approved' : 'rejected', supporting_info: params[:reason])
          log_admin_action(approved ? 'approve_mini_app_appeal' : 'reject_mini_app_appeal', appeal.miniapp.app_id,
            appeal_id: appeal.id, reason: params[:reason])
        end
      end
      redirect_to admin_mini_app_reviews_path(queue: 'appeals'), notice: 'Appeal decision recorded.'
    rescue ActiveRecord::RecordInvalid
      redirect_to admin_mini_app_reviews_path(queue: 'appeals'), alert: 'The appeal decision could not be completed. Check the app configuration.'
    end

    private

    def review_submission(action)
      @mini_app.with_lock do
        return head :unprocessable_entity unless %w[pending_review under_review appeal_submitted].include?(@mini_app.status)
        yield
        log_admin_action(action, @mini_app.app_id, reason: params[:reason])
      end
      redirect_to admin_mini_app_path(@mini_app), notice: 'Review decision recorded.'
    rescue ActiveRecord::RecordInvalid
      redirect_to admin_mini_app_review_path(@mini_app), alert: 'The review could not be completed. Check the launch configuration and OAuth redirects.'
    end

    def validate_decision!
      head :unprocessable_entity unless %w[pending_review under_review appeal_submitted].include?(@mini_app.status) && params[:reason].to_s.strip.length.between?(5, 1000)
    end

    def set_mini_app
      @mini_app = MiniApp.find(params[:id] || params[:mini_app_id])
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_mini_app_reviews_path, alert: "Mini-app not found."
    end
  end
end
