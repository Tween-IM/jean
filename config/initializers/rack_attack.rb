# TMCP Protocol Section 11.4.1: Rate Limiting Implementation
# Using Rack::Attack for token bucket algorithm as required

class Rack::Attack
  # Configure cache store (uses Rails cache by default)
  # cache.store = ActiveSupport::Cache::MemoryStore.new

  # TMCP Required Rate Limits (Section 11.4.1)
  # Default: 100 requests per minute
  throttle("req/ip", limit: 100, period: 1.minute) do |req|
    req.ip unless req.path.start_with?("/health")
  end

  # OAuth endpoints: 10 requests per minute (stricter for security)
  throttle("oauth/ip", limit: 10, period: 1.minute) do |req|
    req.ip if req.path.match?(%r{/oauth2/(authorize|token)})
  end

  # Payment operations: 30 requests per minute
  throttle("payments/ip", limit: 30, period: 1.minute) do |req|
    req.ip if req.path.match?(%r{/api/v1/.*/p(?:ayments?|2p)/})
  end

  # Wallet operations: 100 requests per minute
  throttle("wallet/ip", limit: 100, period: 1.minute) do |req|
    req.ip if req.path.match?(%r{/wallet/v1/})
  end

  # User resolution: 100 requests per minute per user
  throttle("resolve/user", limit: 100, period: 1.minute) do |req|
    if req.path.match?(%r{/wallet/v1/resolve/})
      # Extract user ID from Authorization header (TEP token)
      auth_header = req.get_header("HTTP_AUTHORIZATION")
      if auth_header&.start_with?("Bearer ")
        token = auth_header.sub("Bearer ", "")
        begin
          payload = TepTokenService.decode(token)
          payload["sub"] # Matrix user ID
        rescue
          nil
        end
      end
    end
  end

  # Batch resolution: 1000 requests per hour per user
  throttle("resolve_batch/user", limit: 1000, period: 1.hour) do |req|
    if req.path.match?(%r{/wallet/v1/resolve/batch})
      auth_header = req.get_header("HTTP_AUTHORIZATION")
      if auth_header&.start_with?("Bearer ")
        token = auth_header.sub("Bearer ", "")
        begin
          payload = TepTokenService.decode(token)
          payload["sub"] # Matrix user ID
        rescue
          nil
        end
      end
    end
  end

  # MFA verification: 3 attempts per challenge
  throttle("mfa/challenge", limit: 3, period: 5.minutes) do |req|
    if req.path.match?(%r{/mfa/verify})
      req.params["challenge_id"] || req.ip
    end
  end

  # Custom response for rate limited requests
  self.throttled_response = lambda do |env|
    now = Time.current.to_i
    match_data = env["rack.attack.match_data"]

    headers = {
      "Content-Type" => "application/json",
      "X-RateLimit-Limit" => match_data[:limit].to_s,
      "X-RateLimit-Remaining" => "0",
      "X-RateLimit-Reset" => (now + (match_data[:period] - now % match_data[:period])).to_s,
      "Retry-After" => match_data[:period].to_s
    }

    [ 429, headers, [ {
      error: {
        code: "RATE_LIMIT_EXCEEDED",
        message: "Too many requests",
        limit: match_data[:limit],
        period: match_data[:period],
        reset_at: now + (match_data[:period] - now % match_data[:period])
      }
    }.to_json ] ]
  end

  # Safelist health checks
  safelist("allow_health_checks") do |req|
    req.path == "/health" || req.path == "/up"
  end

  # Blocklist for suspicious patterns (optional enhancement)
  blocklist("block_suspicious") do |req|
    req.ip if req.path.match?(%r{\.\./}) # Path traversal attempts
  end
end

# Enable Rack::Attack middleware
Rails.application.config.middleware.use Rack::Attack
