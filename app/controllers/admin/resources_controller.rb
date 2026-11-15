module Admin
  class ResourcesController < BaseController
    before_action :set_resource
    before_action :authorize_resource!

    def index
      @data = client.list(params[:resource], page: params[:page], query: params[:query], status: params[:status], cursor: params[:cursor])
    rescue RemoteClient::Unavailable, RemoteClient::Forbidden, RemoteClient::NotFound, RemoteClient::Rejected => e
      @error = e.message
    end

    def show
      @record = client.detail(params[:resource], params[:id]).fetch("record")
    rescue RemoteClient::Unavailable, RemoteClient::Forbidden, RemoteClient::NotFound, RemoteClient::Rejected => e
      @error = e.message
    end

    def command
      permission = { [ "wallets", "set_status" ] => :manage_wallets,
        [ "pending_transfers", "cancel" ] => :manage_pending_transfers,
        [ "api_keys", "revoke" ] => :manage_api_keys, [ "webhooks", "set_active" ] => :manage_webhooks,
        [ "webhooks", "reset_failures" ] => :manage_webhooks,
        [ "compliance_checks", "review" ] => :approve_kyc,
        [ "rooms", "block" ] => :manage_messaging, [ "rooms", "unblock" ] => :manage_messaging,
        [ "reports", "dismiss" ] => :manage_messaging }[[ params[:resource], params[:operation] ]]
      return head :forbidden unless permission && current_admin_user.has_admin_permission?(permission)
      return head :unprocessable_entity unless params[:reason].to_s.strip.length.between?(5, 1000) &&
        params[:command_id].to_s.match?(/\A[0-9a-f-]{36}\z/i)
      event = AdminAuditEvent.create!(actor_matrix_id: current_admin_user.matrix_user_id,
        action: params[:operation], target: "#{params[:resource]}/#{params[:id]}",
        request_id: params[:command_id], outcome: "pending", details: { reason: params[:reason] })
      client.command(params[:resource], params[:id], action: params[:operation],
        reason: params[:reason], request_id: params[:command_id], value: params[:value])
      event.update!(outcome: "success")
      destination = params[:operation] == "dismiss" ? admin_resource_path(params[:resource]) : admin_resource_record_path(params[:resource], params[:id])
      redirect_to destination, notice: "Action completed."
    rescue RemoteClient::Unavailable, RemoteClient::Forbidden, RemoteClient::NotFound, RemoteClient::Rejected => e
      event&.update!(outcome: e.is_a?(RemoteClient::Unavailable) ? "unknown" : "failed")
      redirect_to admin_resource_record_path(params[:resource], params[:id]), alert: e.message
    end

    private

    def set_resource
      @resource = Resources::CATALOG[params[:resource]]
      head :not_found unless @resource
    end

    def authorize_resource!
      head :forbidden unless current_admin_user.has_admin_permission?(@resource[:permission])
    end

    def client
      @client ||= @resource[:service] == :matrix ? SynapseClient.new : TweenPay::AdminClient.new(current_admin_user)
    end
  end
end
