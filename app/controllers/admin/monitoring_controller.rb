module Admin
  class MonitoringController < BaseController
    QUEUES = {
      'verification_attempts' => ['Identity checks needing review', 'needs_review'],
      'risk_reviews' => ['Flagged risk assessments', 'flagged'],
      'disputes' => ['Open order disputes', 'open'],
      'social_reports' => ['Content reports awaiting review', 'pending'],
      'webhook_deliveries' => ['Failed webhook deliveries', 'failed']
    }.freeze

    def index
      @queues = QUEUES.select { |key, _| current_admin_user.has_admin_permission?(Resources::CATALOG.fetch(key)[:permission]) }
      head :forbidden if @queues.empty?
    end

    def queue
      @key = params[:queue]
      return head :not_found unless QUEUES.key?(@key)
      @resource = Resources::CATALOG.fetch(@key)
      return head :forbidden unless current_admin_user.has_admin_permission?(@resource[:permission])
      @title, @status = QUEUES.fetch(@key)
      client = @resource[:service] == :local ? LocalResourceClient.new(@resource, actor: current_admin_user) : TweenPay::AdminClient.new(current_admin_user)
      @data = client.list(@key, status: @status, page: 1)
      response.headers['Cache-Control'] = 'private, no-store'
      render layout: false
    rescue RemoteClient::Unavailable, RemoteClient::Forbidden, RemoteClient::NotFound, RemoteClient::Rejected => error
      @error = error.message
      render layout: false
    end
  end
end
