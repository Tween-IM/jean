module Admin
  class ActivityController < BaseController
    before_action -> { require_admin_permission!(:view_audit) }
    def index
      @stream = params[:stream] == 'payments' ? 'payments' : 'workspace'
      if @stream == 'payments'
        @data = TweenPay::AdminClient.new(current_admin_user).list('payment_audit', page: params[:page], query: params[:query])
      else
        scope = AdminAuditEvent.order(created_at: :desc)
        if params[:query].present?
          pattern = "%#{AdminAuditEvent.sanitize_sql_like(params[:query].to_s.first(200))}%"
          scope = scope.where('actor_matrix_id ILIKE :q OR action ILIKE :q OR target ILIKE :q', q: pattern)
        end
        @events = paginate(scope)
      end
    rescue RemoteClient::Unavailable, RemoteClient::Forbidden, RemoteClient::NotFound, RemoteClient::Rejected => error
      @error = error.message
    end
  end
end
