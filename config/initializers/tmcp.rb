# TMCP Server Configuration
# Environment-specific settings for TMCP Protocol implementation

Rails.application.configure do
  # TMCP Protocol Constants
  config.tmcp = {
    # JWT Token Configuration
    jwt_issuer: ENV["TMCP_JWT_ISSUER"] || "https://tmcp.example.com",
    jwt_key_id: ENV["TMCP_JWT_KEY_ID"] || "tmcp-2024-12",
    jwt_algorithm: "RS256",

    # OAuth 2.0 Configuration
    oauth_authorization_code_expiry: 10.minutes,
    oauth_access_token_expiry: 1.hour,
    oauth_refresh_token_expiry: 30.days,

    # Payment Configuration
    payment_request_expiry: 5.minutes,
    p2p_transfer_expiry: 24.hours,
    max_transaction_amount: 50000.00,
    mfa_threshold: 50.00,

    # Rate Limiting (requests per minute)
    rate_limits: {
      oauth_token: 60,
      wallet_balance: 30,
      wallet_transactions: 20,
      p2p_transfer: 10,
      payment_request: 20,
      miniapp_api: 100
    },

    # Matrix Integration
    matrix_api_timeout: 30.seconds,
    matrix_event_retry_attempts: 3,

    # Storage Limits
    storage_max_keys_per_user: 1000,
    storage_max_key_size: 1.megabyte,
    storage_max_total_size: 10.megabytes,

    # Gift Configuration
    gift_max_count: 100,
    gift_default_expiry: 24.hours,
    gift_min_participants: 2,

    # Security
    hmac_secret: ENV["TMCP_HMAC_SECRET"],
    encryption_key: ENV["TMCP_ENCRYPTION_KEY"]
  }.freeze
end

# TMCP-specific configuration access
module TMCP
  def self.config
    Rails.application.config.tmcp
  end
end
