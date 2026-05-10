module Admin
  class DashboardController < BaseController
    def index
      @stats = {
        total_users: User.count,
        active_users: User.where(status: :active).count,
        suspended_users: User.where(status: :suspended).count,
        total_mini_apps: MiniApp.count,
        active_mini_apps: MiniApp.where(status: :active).count,
        total_installations: MiniappInstallation.count,
        total_storage_entries: StorageEntry.count,
        total_gifts: safe_count(GroupGift),
        total_oauth_apps: Doorkeeper::Application.count,
        total_oauth_tokens: Doorkeeper::AccessToken.count
      }

      @recent_users = User.order(created_at: :desc).limit(5)
      @recent_mini_apps = MiniApp.order(created_at: :desc).limit(5)
      @pending_approvals = AuthorizationApproval.where(approved_at: nil).order(created_at: :desc).limit(5)
    end

    private

    def safe_count(model)
      model.count
    rescue ActiveRecord::StatementInvalid
      0
    end
  end
end
