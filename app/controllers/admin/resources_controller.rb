module Admin
  class ResourcesController < BaseController
    before_action :set_resource
    before_action :authorize_resource!

    def index
      return redirect_to admin_activity_path(stream: "payments") if params[:resource] == "payment_audit"
      if %w[payment_accounts verifications].include?(params[:resource])
        return redirect_to admin_users_path(query: params[:query])
      end
      @data = client.list(params[:resource], page: params[:page], query: params[:query], status: params[:status], cursor: params[:cursor], sort: params[:sort])
    rescue RemoteClient::Unavailable, RemoteClient::Forbidden, RemoteClient::NotFound, RemoteClient::Rejected => e
      @needs_authorization = e.is_a?(AdminOauthGrant::ConnectionRequired)
      @error = e.message
    end

    def show
      payload = client.detail(params[:resource], params[:id])
      @record = payload.fetch("record")
      if %w[payment_accounts verifications].include?(params[:resource])
        person = User.find_by(matrix_user_id: @record['customer_matrix_id'].presence || @record['matrix_user_id'])
        if person
          return redirect_to admin_user_path(person, tab: params[:resource] == 'verifications' ? 'compliance' : 'payments')
        end
      end
      @related_transactions = payload["transactions"]
      @savings_transactions = payload["savings_transactions"]
      @evidence = payload["evidence"]
      @card_requests = payload["card_requests"]
      @verification_attempts = payload["verification_attempts"]
      @verification_evidence = client.evidence(params[:id], resource: "verification_attempts") if params[:resource] == "verification_attempts"
      response.headers["Cache-Control"] = "private, no-store" if @verification_evidence
      if params[:resource] == "payment_accounts" && current_admin_user.has_admin_permission?(:manage_cards)
        begin
          @card_options = client.card_options.fetch("options")
        rescue RemoteClient::Unavailable, RemoteClient::Rejected, RemoteClient::Forbidden
          @card_options = []
        end
      end
    rescue RemoteClient::Unavailable, RemoteClient::Forbidden, RemoteClient::NotFound, RemoteClient::Rejected => e
      @needs_authorization = e.is_a?(AdminOauthGrant::ConnectionRequired)
      @error = e.message
    end

    def command
      permission = Operations::PERMISSIONS.dig(params[:resource], params[:operation])
      return head :forbidden unless permission && current_admin_user.has_admin_permission?(permission)
      return head :unprocessable_entity unless params[:reason].to_s.strip.length.between?(5, 1000) &&
        params[:command_id].to_s.match?(/\A[0-9a-f-]{36}\z/i)
      event = AdminAuditEvent.create!(actor_matrix_id: current_admin_user.matrix_user_id,
        action: params[:operation], target: "#{params[:resource]}/#{params[:id]}",
        request_id: params[:command_id], outcome: "pending", details: { reason: params[:reason] })
      result = client.command(params[:resource], params[:id], action: params[:operation],
        reason: params[:reason], request_id: params[:command_id], value: Operations.arguments(params[:operation], params))
      event.update!(outcome: "success")
      return redirect_to admin_resource_record_path(result["resource"], result["record_id"]), notice: "Provider request accepted. Refresh the card to check its current status." if result.is_a?(Hash) && result["record_id"] && result["resource"] == "cards"
      destination = params[:operation] == "dismiss" ? admin_resource_path(params[:resource]) : admin_resource_record_path(params[:resource], params[:id])
      redirect_to destination, notice: "Action completed."
    rescue ArgumentError, KeyError, JSON::ParserError
      event&.update!(outcome: "failed")
      redirect_to admin_resource_record_path(params[:resource], params[:id]), alert: "Check the amounts and selected options. Use at most two decimal places."
    rescue RemoteClient::Unavailable, RemoteClient::Forbidden, RemoteClient::NotFound, RemoteClient::Rejected => e
      event&.update!(outcome: e.is_a?(RemoteClient::Unavailable) ? "unknown" : "failed")
      redirect_to admin_resource_record_path(params[:resource], params[:id]), alert: e.message
    end

    def evidence
      return head :forbidden unless %w[identity_documents verification_attempts].include?(params[:resource]) && current_admin_user.has_admin_permission?(:view_kyc)
      payload = client.evidence(params[:id], resource: params[:resource], image: params[:image], raw: params[:raw])
      bytes = Base64.strict_decode64(payload.fetch("content"))
      type = payload.fetch("content_type")
      return head :unprocessable_entity unless %w[application/pdf application/json image/jpeg image/png image/webp].include?(type) && bytes.bytesize <= 10.megabytes
      response.headers["Cache-Control"] = "private, no-store"
      response.headers["Content-Security-Policy"] = "sandbox; default-src 'none'"
      response.headers["X-Content-Type-Options"] = "nosniff"
      extension = { "application/pdf" => "pdf", "application/json" => "json", "image/jpeg" => "jpg", "image/png" => "png", "image/webp" => "webp" }.fetch(type)
      send_data bytes, type: type, disposition: (type == "application/json" ? "attachment" : "inline"), filename: "verification-evidence.#{extension}"
    rescue RemoteClient::Unavailable, RemoteClient::Forbidden, RemoteClient::NotFound, RemoteClient::Rejected, KeyError, ArgumentError
      render plain: "Evidence is unavailable. Ask the customer to upload a valid supported document.", status: :unprocessable_entity
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
      @client ||= case @resource[:service]
      when :matrix then SynapseClient.new(grant: admin_oauth_grant)
      when :local then LocalResourceClient.new(@resource, actor: current_admin_user)
      else TweenPay::AdminClient.new(current_admin_user)
      end
    end
  end
end
