module Admin
  class ActivityController < BaseController
    before_action -> { require_admin_permission!(:view_audit) }
    def index
      @events = paginate(AdminAuditEvent.order(created_at: :desc))
    end
  end
end
