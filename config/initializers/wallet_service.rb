# TMCP Wallet Service Configuration
# Real wallet service integration with Tween Pay API

TMCP_CONFIG = {
  wallet_api: {
    base_url: ENV.fetch("WALLET_API_BASE_URL", "http://localhost:3001"), # Default to local tween-pay service
    api_key: ENV.fetch("WALLET_API_KEY", ""),
    timeout: ENV.fetch("WALLET_API_TIMEOUT", 30).to_i,
    retry_attempts: ENV.fetch("WALLET_API_RETRY_ATTEMPTS", 3).to_i
  }
}

# Configure Faraday for wallet service calls
Faraday.default_adapter = :net_http
Faraday.default_connection_options = {
  request: {
    timeout: TMCP_CONFIG[:wallet_api][:timeout],
    open_timeout: 5
  }
}
