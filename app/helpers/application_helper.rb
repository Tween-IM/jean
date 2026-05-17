module ApplicationHelper
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
