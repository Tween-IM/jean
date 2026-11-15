module Admin
  module Resources
    # One resource vocabulary for the workspace; backend names never become navigation sections.
    CATALOG = {
      "wallets" => { label: "Wallets", group: "Money", icon: "money", permission: :view_wallets, service: :payments, fields: %w[id currency balance_cents status accountable_type accountable_id created_at] },
      "transactions" => { label: "Transactions", group: "Money", icon: "money", permission: :view_transactions, service: :payments, fields: %w[id reference_id amount_cents currency status type created_at] },
      "pending_transfers" => { label: "Pending transfers", group: "Money", icon: "money", permission: :view_pending_transfers, service: :payments, fields: %w[id reference amount_cents currency status created_at] },
      "businesses" => { label: "Businesses", group: "Money", icon: "building", permission: :view_businesses, service: :payments, fields: %w[id name status created_at] },
      "bank_accounts" => { label: "Bank accounts", group: "Money", icon: "building", permission: :view_bank_accounts, service: :payments, fields: %w[id bank_name currency provider account_type created_at] },
      "pockets" => { label: "Pockets", group: "Money", icon: "money", permission: :view_wallets, service: :payments, fields: %w[id name currency balance_cents status created_at] },
      "stashes" => { label: "Stashes", group: "Money", icon: "money", permission: :view_wallets, service: :payments, fields: %w[id name currency balance_cents status created_at] },
      "compliance_checks" => { label: "Compliance reviews", group: "Money", icon: "checkmark", permission: :view_kyc, service: :payments, fields: %w[id check_type status checkable_type checkable_id created_at] },
      "bills" => { label: "Bills", group: "Money", icon: "document", permission: :view_bills, service: :payments, fields: %w[id reference amount_cents currency status created_at] },
      "rooms" => { label: "Rooms", group: "Messaging", icon: "people", permission: :view_messaging, service: :matrix, fields: %w[room_id name canonical_alias joined_members encryption] },
      "reports" => { label: "Reports", group: "Messaging", icon: "alert", permission: :view_messaging, service: :matrix, fields: %w[id room_id user_id reason received_ts] },
      "api_keys" => { label: "API keys", group: "Platform", icon: "settings", permission: :view_api_keys, service: :payments, fields: %w[id name active business_id expires_at created_at] },
      "webhooks" => { label: "Webhooks", group: "Platform", icon: "settings", permission: :view_webhooks, service: :payments, fields: %w[id active failure_count business_id created_at] },
      "notifications" => { label: "Notifications", group: "Platform", icon: "alert", permission: :view_notifications, service: :payments, fields: %w[id notification_type title user_id read_at created_at] }
    }.freeze
  end
end
