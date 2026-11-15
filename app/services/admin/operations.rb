module Admin
  module Operations
    PERMISSIONS = {
      "verification_attempts" => { "approve_attempt" => :approve_kyc, "reject_attempt" => :reject_kyc },
      "wallets" => { "set_status" => :manage_wallets },
      "pending_transfers" => { "cancel" => :manage_pending_transfers },
      "api_keys" => { "revoke" => :manage_api_keys },
      "webhooks" => { "set_active" => :manage_webhooks, "reset_failures" => :manage_webhooks },
      "compliance_checks" => { "review" => :approve_kyc },
      "identity_documents" => { "approve_document" => :approve_kyc, "reject_document" => :reject_kyc },
      "cards" => { "freeze_card" => :manage_cards, "unfreeze_card" => :manage_cards, "terminate_card" => :manage_cards, "sync_card" => :manage_cards },
      "payment_accounts" => { "issue_card" => :manage_cards, "reconcile_issuance" => :manage_cards, "reset_kyc" => :manage_users },
      "pockets" => { "refund_balance" => :manage_savings, "reverse_transaction" => :manage_savings },
      "stashes" => { "refund_balance" => :manage_savings, "reverse_transaction" => :manage_savings },
      "scheduled_transfers" => { "pause" => :manage_savings, "resume" => :manage_savings },
      "saving_rules" => { "pause" => :manage_savings, "resume" => :manage_savings },
      "disputes" => { "resolve_dispute" => :manage_disputes, "review" => :manage_disputes },
      "reviews" => { "approve" => :manage_catalog, "reject" => :manage_catalog },
      "social_posts" => { "hide" => :manage_social_moderation, "restore" => :manage_social_moderation },
      "social_reports" => { "review" => :manage_social_moderation, "resolve" => :manage_social_moderation, "dismiss" => :manage_social_moderation },
      "stories" => { "remove" => :manage_social_moderation },
      "rooms" => { "block" => :manage_messaging, "unblock" => :manage_messaging },
      "reports" => { "dismiss" => :manage_messaging }
    }.freeze

    def self.arguments(operation, params)
      values = if params[:arguments].present?
        raise ArgumentError unless params[:arguments].is_a?(ActionController::Parameters)
        params.require(:arguments).permit(:amount, :transaction_id, :outcome, :seller_amount, :buyer_amount, :price, :acknowledged, :evidence_digest).to_h.stringify_keys
      else
        {}
      end
      case operation
      when "approve_attempt", "reject_attempt"
        { acknowledged: values["acknowledged"] == "1", evidence_digest: values.fetch("evidence_digest") }.to_json
      when "refund_balance"
        { amount_cents: cents(values.fetch("amount")) }.to_json
      when "reverse_transaction"
        { transaction_id: Integer(values.fetch("transaction_id"), 10) }.to_json
      when "resolve_dispute"
        { outcome: values.fetch("outcome"), seller_amount_cents: cents(values.fetch("seller_amount")),
          buyer_refund_cents: cents(values.fetch("buyer_amount")) }.to_json
      when "issue_card"
        quote = JSON.parse(values.fetch("price"))
        raise ArgumentError unless quote.is_a?(Hash)
        quote.slice("program_id", "price_id", "charge_cents", "charge_currency").to_json
      else params[:value]
      end
    end

    def self.cents(value)
      raise ArgumentError unless value.to_s.match?(/\A\d{1,13}(?:\.\d{1,2})?\z/)
      (BigDecimal(value.to_s) * 100).to_i
    end
  end
end
