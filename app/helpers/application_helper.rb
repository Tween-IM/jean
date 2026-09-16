module ApplicationHelper
  # Badges in the admin layout count things that may not exist in a given
  # deployment. Probe for the table first: a failed statement aborts the
  # surrounding transaction, so the zero returned here would be followed by
  # failures everywhere else on the page instead of just a missing badge.
  def safe_count(relation)
    return 0 unless safe_count_ready?(relation)

    relation.count
  rescue ActiveRecord::StatementInvalid => e
    Rails.logger.error "safe_count failed for #{relation}: #{e.message}"
    0
  end

  def safe_count_ready?(subject)
    model = subject.respond_to?(:klass) ? subject.klass : subject
    model.respond_to?(:table_exists?) && model.table_exists?
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError => e
    Rails.logger.error "safe_count probe failed for #{subject}: #{e.message}"
    false
  end

  PERMISSIONS_CATEGORIES = {
    "User" => [
      { key: "user:read", description: "Read basic profile (name, avatar)", sensitivity: "low" },
      { key: "user:read:extended", description: "Read extended profile (status, bio)", sensitivity: "medium" },
      { key: "user:read:contacts", description: "Read friend list", sensitivity: "high" },
    ],
    "Wallet" => [
      { key: "wallet:balance", description: "Read wallet balance", sensitivity: "high" },
      { key: "wallet:pay", description: "Process payments", sensitivity: "critical" },
      { key: "wallet:history", description: "Read transaction history", sensitivity: "high" },
      { key: "wallet:request", description: "Request payments from users", sensitivity: "high" },
    ],
    "Messaging" => [
      { key: "messaging:send", description: "Send messages to rooms", sensitivity: "high" },
      { key: "messaging:read", description: "Read message history", sensitivity: "high" },
    ],
    "Storage" => [
      { key: "storage:read", description: "Read mini-app storage", sensitivity: "low" },
      { key: "storage:write", description: "Write to mini-app storage", sensitivity: "low" },
    ],
    "Room" => [
      { key: "room:create", description: "Create new rooms", sensitivity: "high" },
      { key: "room:invite", description: "Invite users to rooms", sensitivity: "high" },
    ],
    "Webhook" => [
      { key: "webhook:send", description: "Receive webhook callbacks", sensitivity: "medium" },
    ],
    "Matrix" => [
      { key: "urn:matrix:org.matrix.msc2967.client:api:*", description: "Full Matrix C-S API access", sensitivity: "high" },
      { key: "urn:matrix:org.matrix.msc2967.client:device:[device_id]", description: "Device-specific operations", sensitivity: "medium" },
    ],
  }.freeze
end
