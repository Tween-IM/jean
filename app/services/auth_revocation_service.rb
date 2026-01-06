class AuthRevocationService
  mattr_accessor :revoked_tokens_cache
  self.revoked_tokens_cache = Rails.cache

  def self.revoke_permissions(user_id:, miniapp_id:, scopes:, reason: "user_initiated")
    raise ArgumentError, "user_id is required" if user_id.blank?
    raise ArgumentError, "miniapp_id is required" if miniapp_id.blank?

    revoked_at = Time.current.to_i

    invalidated_tokens = invalidate_tep_tokens(user_id, miniapp_id, scopes)

    revocation_event = create_revocation_event(user_id, miniapp_id, scopes, reason, revoked_at)

    send_webhook_notification(user_id, miniapp_id, scopes, reason, revoked_at)

    notify_mas(user_id, miniapp_id, scopes)

    {
      success: true,
      user_id: user_id,
      miniapp_id: miniapp_id,
      revoked_scopes: scopes,
      invalidated_tokens_count: invalidated_tokens,
      revoked_at: Time.current.iso8601,
      reason: reason,
      revocation_event_id: revocation_event[:event_id]
    }
  end

  def self.user_revoke_all(user_id:, miniapp_id:)
    raise ArgumentError, "user_id is required" if user_id.blank?
    raise ArgumentError, "miniapp_id is required" if miniapp_id.blank?

    scopes = get_all_granted_scopes(user_id, miniapp_id)

    revoke_permissions(
      user_id: user_id,
      miniapp_id: miniapp_id,
      scopes: scopes,
      reason: "user_initiated"
    )
  end

  def self.handle_webhook(data)
    case data["event"]
    when "token_revoked"
      handle_token_revoked_webhook(data)
    when "permission_changed"
      handle_permission_changed_webhook(data)
    else
      { status: "ignored", event: data["event"] }
    end
  end

  def self.invalidate_tep_tokens(user_id, miniapp_id, scopes)
    pattern = "tep_revoked:#{user_id}:#{miniapp_id}:*"
    keys = revoked_tokens_cache.keys(pattern)

    scope_set = Set.new(scopes)
    invalidated_count = 0

    keys.each do |key|
      cached_scopes = revoked_tokens_cache.read(key)
      cached_scope_set = Set.new(cached_scopes || [])

      next unless scope_set.subset?(cached_scope_set)

      revoked_tokens_cache.delete(key)
      invalidated_count += 1
    end

    invalidate_user_sessions(user_id, miniapp_id, scopes)

    invalidated_count
  end

  def self.invalidate_user_sessions(user_id, miniapp_id, scopes)
    session_pattern = "user_session:#{user_id}:#{miniapp_id}:*"
    session_keys = revoked_tokens_cache.keys(session_pattern)

    session_keys.each do |key|
      session_data = revoked_tokens_cache.read(key)
      next if session_data.nil?

      session_scopes = Set.new(session_data["scopes"] || [])
      scope_set = Set.new(scopes)

      if scope_set.subset?(session_scopes)
        revoked_tokens_cache.delete(key)
        revoke_matrix_tokens(session_data["mas_refresh_token_id"])
      end
    end
  end

  def self.create_revocation_event(user_id, miniapp_id, scopes, reason, revoked_at)
    event_content = {
      authorized: false,
      revoked_at: revoked_at,
      revoked_scopes: scopes,
      reason: reason,
      tmcp_scopes: scopes,
      matrix_scopes: [ "urn:matrix:org.matrix.msc2967.client:api:*" ]
    }

    event = {
      type: "m.room.tween.authorization",
      state_key: miniapp_id,
      content: event_content,
      sender: user_id,
      room_id: nil
    }

    MatrixEventService.publish_authorization_revoked(
      user_id: user_id,
      miniapp_id: miniapp_id,
      revoked_scopes: scopes,
      reason: reason
    )

    { event_id: "rev_#{revoked_at}_#{miniapp_id}", content: event_content }
  end

  def self.send_webhook_notification(user_id, miniapp_id, scopes, reason, revoked_at)
    miniapp = MiniApp.find_by(miniapp_id: miniapp_id)
    return unless miniapp&.webhook_url?

    payload = {
      event: "authorization_revoked",
      user_id: user_id,
      miniapp_id: miniapp_id,
      revoked_scopes: scopes,
      reason: reason,
      revoked_at: revoked_at,
      timestamp: Time.current.iso8601
    }

    signature = WebhookService.sign_payload(payload, miniapp.webhook_secret)

    WebhookService.dispatch(
      url: miniapp.webhook_url,
      payload: payload,
      signature: signature
    )
  rescue => e
    Rails.logger.error "Failed to send revocation webhook: #{e.message}"
    { webhook_failed: true, error: e.message }
  end

  def self.notify_mas(user_id, miniapp_id, scopes)
    mas_client = MasClientService.new
    mas_client.revoke_user_permissions(
      user_id: user_id,
      client_id: miniapp_id,
      scopes: scopes
    )
  rescue => e
    Rails.logger.error "Failed to notify MAS: #{e.message}"
  end

  def self.get_all_granted_scopes(user_id, miniapp_id)
    approval_scope = ApprovalScope.where(
      user_id: user_id,
      miniapp_id: miniapp_id
    )

    approval_scope.pluck(:scope)
  end

  def self.handle_token_revoked_webhook(data)
    user_id = data["user_id"]
    miniapp_id = data["miniapp_id"]

    invalidate_tep_tokens(user_id, miniapp_id, data["scopes"] || [])

    { status: "processed", event: "token_revoked" }
  end

  def self.handle_permission_changed_webhook(data)
    user_id = data["user_id"]
    miniapp_id = data["miniapp_id"]

    ApprovalScope.where(
      user_id: user_id,
      miniapp_id: miniapp_id
    ).destroy_all

    { status: "processed", event: "permission_changed" }
  end

  def self.revoke_matrix_tokens(refresh_token_id)
    return if refresh_token_id.blank?

    mas_client = MasClientService.new
    mas_client.revoke_token(refresh_token_id)
  rescue => e
    Rails.logger.error "Failed to revoke Matrix tokens: #{e.message}"
  end

  def self.is_revoked?(user_id, miniapp_id, scope)
    pattern = "tep_revoked:#{user_id}:#{miniapp_id}:#{scope}"
    revoked_tokens_cache.exist?(pattern)
  end
end
