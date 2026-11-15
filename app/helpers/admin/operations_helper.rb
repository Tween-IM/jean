module Admin::OperationsHelper
  def admin_operations(key, record)
    state = record["status"]
    rows = case key
    when "wallets" then [ [ "Freeze wallet", "set_status", "frozen" ], [ "Activate wallet", "set_status", "active" ] ]
    when "cards"
      [ [ "Refresh provider status", "sync_card", nil ] ] +
        (state == "active" ? [ [ "Freeze card", "freeze_card", nil ] ] : []) +
        (state == "frozen" ? [ [ "Unfreeze card", "unfreeze_card", nil ] ] : []) +
        (%w[active frozen].include?(state) ? [ [ "Terminate card permanently", "terminate_card", nil ] ] : [])
    when "payment_accounts"
      [ [ "Reset KYC to tier zero", "reset_kyc", nil ] ] + (@card_options.present? ? [ [ "Issue an unfunded virtual card", "issue_card", nil ] ] : [])
    when "pockets", "stashes" then [ [ "Return balance to the customer wallet", "refund_balance", nil ] ]
    when "identity_documents"
      state == "pending" ? [ [ "Approve document", "approve_document", nil ], [ "Reject document", "reject_document", nil ] ] : []
    when "scheduled_transfers", "saving_rules"
      state == "active" ? [ [ "Pause automation", "pause", nil ] ] : (state == "paused" ? [ [ "Resume automation", "resume", nil ] ] : [])
    when "pending_transfers" then %w[completed cancelled].include?(state) ? [] : [ [ "Cancel transfer", "cancel", nil ] ]
    when "api_keys" then record["active"] ? [ [ "Revoke key", "revoke", nil ] ] : []
    when "webhooks" then [ [ "Enable webhook", "set_active", "true" ], [ "Disable webhook", "set_active", "false" ], [ "Reset failures", "reset_failures", nil ] ]
    when "compliance_checks" then [ [ "Approve review", "review", "passed" ], [ "Reject review", "review", "failed" ], [ "Mark in review", "review", "in_review" ] ]
    when "disputes" then %w[open under_review].include?(state) ? [ [ "Start case review", "review", nil ], [ "Resolve protected-payment dispute", "resolve_dispute", nil ] ] : []
    when "reviews" then [ [ "Approve review", "approve", nil ], [ "Reject review", "reject", nil ] ]
    when "social_posts" then [ [ "Hide post from feeds", "hide", nil ], [ "Restore post moderation approval", "restore", nil ] ]
    when "social_reports" then [ [ "Start report review", "review", nil ], [ "Resolve report", "resolve", nil ], [ "Dismiss report", "dismiss", nil ] ]
    when "stories" then state == "deleted" ? [] : [ [ "Remove story", "remove", nil ] ]
    when "rooms" then [ [ "Block room", "block", nil ], [ "Unblock room", "unblock", nil ] ]
    when "reports" then [ [ "Dismiss report", "dismiss", nil ] ]
    else []
    end
    rows.select { |_, operation, _| permission = Admin::Operations::PERMISSIONS.dig(key, operation); permission && current_admin_user.has_admin_permission?(permission) }
  end

  def admin_safe_evidence_url(value)
    uri = URI.parse(value.to_s)
    uri.to_s if uri.scheme == "https" && uri.host.present? && uri.userinfo.nil?
  rescue URI::InvalidURIError
    nil
  end
end
