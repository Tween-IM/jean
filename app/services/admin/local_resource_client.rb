module Admin
  class LocalResourceClient
    def initialize(resource, actor:)
      @actor = actor
      @resource = resource
      @model = resource.fetch(:model).constantize
    end

    def list(_key, query = {})
      scope = @model.order(created_at: query[:sort] == 'oldest' ? :asc : :desc, id: query[:sort] == 'oldest' ? :asc : :desc)
      if query[:status].present? && @model.column_names.include?("status")
        scope = scope.where(status: query[:status])
      end
      columns = %w[name title caption reason body].intersection(@model.column_names)
      if query[:query].present? && columns.any?
        pattern = "%#{@model.sanitize_sql_like(query[:query].to_s.first(200))}%"
        scope = scope.where(columns.map { |column| "#{@model.connection.quote_column_name(column)} ILIKE :term" }.join(" OR "), term: pattern)
      end
      page = [ query[:page].to_i, 1 ].max
      total = scope.count
      { "records" => scope.offset((page - 1) * 25).limit(25).map { |record| present(record) },
        "total" => total, "page" => page, "next_page" => (page + 1 if page * 25 < total) }
    end

    def detail(key, id)
      record = @model.find(id)
      payload = { "record" => present(record) }
      if key == "disputes"
        payload["record"].merge!(record.attributes.slice("description", "opened_at", "resolution", "protected_payment_id"))
        payload["record"]["currency"] = record.commerce_order.currency
        payload["record"]["order_total_cents"] = record.commerce_order.total_cents
        payload["evidence"] = record.evidence.order(:created_at).map { |entry| entry.attributes.slice("caption", "url", "media_type", "uploaded_at") }
      end
      payload
    rescue ActiveRecord::RecordNotFound
      raise RemoteClient::NotFound, "This record could not be found."
    end

    def command(key, id, action:, reason:, request_id:, value: nil)
      permission = Operations::PERMISSIONS.dig(key, action)
      raise RemoteClient::Forbidden, "You cannot perform this action." unless permission && @actor.active? && @actor.has_admin_permission?(permission)
      record = @model.find(id)
      return resolve_dispute(record, reason, request_id, value) if key == "disputes" && action == "resolve_dispute"
      record.with_lock do
        attributes = case [ key, action ]
        when [ "disputes", "review" ] then { status: "under_review" }
        when [ "reviews", "approve" ] then { status: "approved" }
        when [ "reviews", "reject" ] then { status: "rejected" }
        when [ "social_posts", "hide" ] then { moderation_status: "rejected" }
        when [ "social_posts", "restore" ] then { moderation_status: "approved" }
        when [ "social_reports", "review" ] then { status: "reviewing" }
        when [ "social_reports", "resolve" ] then { status: "resolved" }
        when [ "social_reports", "dismiss" ] then { status: "dismissed" }
        when [ "stories", "remove" ] then { status: "deleted" }
        else raise RemoteClient::Forbidden, "This operation is not available."
        end
        raise RemoteClient::Rejected, "This case is already closed." if key == "disputes" && !%w[open under_review].include?(record.status)
        record.update!(attributes)
        AdminAuditEvent.create!(actor_matrix_id: @actor.matrix_user_id, action: "workspace.#{action}",
          target: "#{key}/#{id}", request_id: request_id, details: { reason: reason })
      end
      { "success" => true }
    rescue ActiveRecord::RecordInvalid
      raise RemoteClient::Rejected, "This record cannot move to the selected state."
    end

    def resolve_dispute(dispute, reason, key, value)
      reserved = false
      values = JSON.parse(value)
      fingerprint = Digest::SHA256.hexdigest([ value, reason, @actor.matrix_user_id ].to_json)
      dispute.with_lock do
        if dispute.status == "resolved"
          return { "success" => true } if dispute.resolution["command_id"] == key && dispute.resolution["fingerprint"] == fingerprint
          raise RemoteClient::Rejected, "This dispute has already been resolved."
        end
        raise RemoteClient::Rejected, "This case is already closed." unless %w[open under_review].include?(dispute.status)
        raise RemoteClient::Rejected, "This order has no protected-payment settlement channel." if dispute.protected_payment_id.blank?
        previous = dispute.resolution
        if previous["command_id"] && (previous["command_id"] != key || previous["fingerprint"] != fingerprint)
          raise RemoteClient::Rejected, "Recheck the original settlement request before changing its decision."
        end
        dispute.update!(status: "under_review", resolution: values.merge("command_id" => key,
          "fingerprint" => fingerprint, "phase" => "pending", "reason" => reason))
        reserved = true
      end
      TweenPay::AdminClient.new(@actor).command("protected_payments", dispute.protected_payment_id,
        action: "resolve_dispute", reason: reason, request_id: key, value: value)
      dispute.with_lock do
        dispute.update!(status: "resolved", resolved_at: Time.current, resolved_by_user_id: @actor.matrix_user_id,
          resolution: dispute.resolution.merge("phase" => "completed"))
      end
      { "success" => true }
    rescue RemoteClient::Rejected, RemoteClient::Forbidden, RemoteClient::NotFound
      dispute.with_lock do
        if reserved && dispute.resolution["command_id"] == key && dispute.resolution["phase"] == "pending"
          dispute.update!(resolution: dispute.resolution.except("command_id", "fingerprint").merge("phase" => "rejected"))
        end
      end
      raise
    rescue RemoteClient::Unavailable
      dispute.update!(resolution: dispute.resolution.merge("phase" => "unknown"))
      raise
    end

    private

    def present(record)
      data = record.attributes.slice("id", *@resource.fetch(:fields))
      product = record.respond_to?(:commerce_product) ? record.commerce_product : nil
      merchant = record.respond_to?(:commerce_merchant) ? record.commerce_merchant : nil
      order = record.respond_to?(:commerce_order) ? record.commerce_order : nil
      data["title"] = product&.title.presence || (record.name if record.respond_to?(:name)).presence ||
        (record.caption.to_s.first(100) if record.respond_to?(:caption)).presence ||
        merchant&.display_name.presence || @resource[:label].singularize
      data["subtitle"] = merchant&.display_name.presence || ("Order #{order.order_id}" if order) ||
        (record.reason.to_s.humanize if record.respond_to?(:reason))
      data
    end
  end
end
