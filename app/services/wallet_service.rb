class WalletService
  # TMCP Protocol Section 6: Real Wallet Service Integration
  # Integrated with Tween Pay API at https://wallettween.im

  class WalletError < StandardError
    attr_reader :code

    def initialize(message, code = nil)
      @code = code
      super(message)
    end
  end

  # Circuit breakers for different operations (PROTO Section 7.7)
  # Per-user circuit breakers to prevent one user from affecting others
  # Using Concurrent::Map for thread-safe atomic operations
  require 'concurrent'

  CIRCUIT_BREAKERS = Concurrent::Map.new
  CIRCUIT_BREAKER_ACCESS_TIMES = Concurrent::Map.new
  CIRCUIT_BREAKER_MUTEX = Mutex.new
  MAX_CIRCUIT_BREAKERS = 10_000 # LRU limit

  def self.get_circuit_breaker(user_id, operation)
    key = "#{user_id}:#{operation}"

    # Update access time for LRU tracking (thread-safe)
    CIRCUIT_BREAKER_ACCESS_TIMES[key] = Time.current.to_f

    # Check if we need to evict old entries (do this periodically, not every call)
    if CIRCUIT_BREAKERS.size >= MAX_CIRCUIT_BREAKERS && rand < 0.01 # 1% chance to trigger eviction
      evict_oldest_if_needed
    end

    # Return existing or create new circuit breaker (thread-safe atomic operation)
    # Concurrent::Map has compute_if_absent for atomic operations
    CIRCUIT_BREAKERS.compute_if_absent(key) do
      CircuitBreakerService.new("#{operation}:#{user_id}")
    end
  end

  def self.reset_circuit_breakers_for_user(user_id)
    [ :balance, :payments, :transfers, :verification ].each do |operation|
      key = "#{user_id}:#{operation}"
      CIRCUIT_BREAKERS.delete(key)
      CIRCUIT_BREAKER_ACCESS_TIMES.delete(key)
    end
  end

  def self.circuit_breaker_stats
    {
      total_circuit_breakers: CIRCUIT_BREAKERS.size,
      max_allowed: MAX_CIRCUIT_BREAKERS,
      operations: CIRCUIT_BREAKERS.keys.group_by { |k| k.split(":").last }.transform_values(&:count)
    }
  end

  private

  def self.evict_oldest_if_needed
    # Use mutex only for the eviction operation, not for normal reads
    CIRCUIT_BREAKER_MUTEX.synchronize do
      return unless CIRCUIT_BREAKERS.size >= MAX_CIRCUIT_BREAKERS

      # Sort by access time and remove oldest 10%
      sorted = CIRCUIT_BREAKER_ACCESS_TIMES.sort_by { |_, time| time }
      to_remove = (MAX_CIRCUIT_BREAKERS * 0.1).ceil

      sorted.first(to_remove).each do |key, _|
        CIRCUIT_BREAKERS.delete(key)
        CIRCUIT_BREAKER_ACCESS_TIMES.delete(key)
      end

      Rails.logger.info "[CircuitBreaker] Evicted #{to_remove} old circuit breakers. Remaining: #{CIRCUIT_BREAKERS.size}"
    end
  end

  # Extract a stable identifier from TEP token for per-user circuit breaking.
  # Uses a deterministic hash of the token itself so we never need to decode the JWT.
  def self.extract_user_id_from_tep(tep_token)
    return "anonymous" if tep_token.blank?

    Digest::SHA256.hexdigest(tep_token)[0, 32]
  end

  # Configuration from initializer
  WALLET_API_BASE_URL = ENV.fetch("WALLET_API_BASE_URL", "https://wallet.tween.im")
  WALLET_API_KEY = ENV.fetch("WALLET_API_KEY", "")

  def self.make_wallet_request(method, endpoint, body = nil, headers = {})
    url = "#{WALLET_API_BASE_URL}#{endpoint}"

    default_headers = {
      "Content-Type" => "application/json",
      "Accept" => "application/json"
    }

    if WALLET_API_KEY.present? && !headers["Authorization"]
      default_headers["Authorization"] = "Bearer #{WALLET_API_KEY}"
    end

    headers = default_headers.merge(headers)

    begin
      response = case method.to_sym
      when :get
                   Faraday.get(url, nil, headers)
      when :post
                   Faraday.post(url, body&.to_json, headers)
      when :put
                   Faraday.put(url, body&.to_json, headers)
      when :delete
                   Faraday.delete(url, nil, headers)
      else
                   raise "Unsupported HTTP method: #{method}"
      end

      unless response.success?
        Rails.logger.error "Wallet API error: #{response.status} - #{response.body}"
        begin
          error_data = JSON.parse(response.body)
          if error_data["error"]
            raise WalletError.new(error_data["error"]["message"] || "Wallet service error", error_data["error"]["code"])
          end
        rescue JSON::ParserError
        end
        raise WalletError.new("Wallet service unavailable (HTTP #{response.status})")
      end

      JSON.parse(response.body, symbolize_names: true)
    rescue Faraday::Error => e
      Rails.logger.error "Wallet API connection error: #{e.message}"
      raise WalletError.new("Wallet service unavailable")
    rescue JSON::ParserError => e
      Rails.logger.error "Wallet API response parsing error: #{e.message}"
      raise WalletError.new("Invalid wallet service response")
    end
  end

  def self.ensure_user_registered(matrix_user_id, tep_token)
    return if tep_token.blank?

    begin
      # Try to register the user in wallet service
      register_response = make_wallet_request(:post, "/api/v1/tmcp/wallets/register",
                                            { user_id: matrix_user_id, currency: "NGN" },
                                            { "Authorization" => "Bearer #{tep_token}" })

      Rails.logger.info "Auto-registered user #{matrix_user_id} in wallet service during TEP token issuance"
    rescue WalletError => e
      # If registration fails, log but don't block TEP token issuance
      Rails.logger.warn "Failed to auto-register user #{matrix_user_id} in wallet service: #{e.message}"
    end
  end

  def self.get_balance(user_id, tep_token = nil)
    get_circuit_breaker(user_id, :balance).call do
      Rails.logger.info "Getting balance for user #{user_id}"

      # Call tween-pay TMCP balance endpoint
      data = make_wallet_request(:get, "/api/v1/tmcp/wallets/balance",
                                  nil, { "Authorization" => "Bearer #{tep_token}" })
      data = deep_symbolize_keys(data)

      # Transform response to match jean's expected format
      {
        wallet_id: data[:wallet_id],
          balance: {
            available: data.dig(:balance, :available) || 0.00,
            pending: data.dig(:balance, :pending) || 0.00,
            currency: data.dig(:balance, :currency) || "NGN"
          },
        limits: data[:limits] || {
          daily_limit: 1000.00,
          daily_used: 0.00,
          transaction_limit: 500.00
        },
        verification: data[:verification] || {
          level: 0,
          level_name: "Unverified",
          features: [],
          can_upgrade: true,
          next_level: 1,
          upgrade_requirements: [ "id_verification" ]
        },
        status: data[:status] || "active"
      }
    end
  end

  def self.get_transactions(user_id, limit: 50, offset: 0, tep_token: nil)
    get_circuit_breaker(user_id, :balance).call do
      Rails.logger.info "Getting transactions for user #{user_id}"

      # Call tween-pay TMCP transactions endpoint
      data = make_wallet_request(:get, "/api/v1/tmcp/wallet/transactions?limit=#{limit}&offset=#{offset}",
                                  nil, { "Authorization" => "Bearer #{tep_token}" })
      data = data.symbolize_keys

      # Transform response to match jean's expected format
      {
        transactions: data[:transactions] || [],
        pagination: data[:pagination] || {
          total: 0,
          limit: limit,
          offset: offset,
          has_more: false
        }
      }
    end
  end

  def self.resolve_user(user_id, tep_token: nil)
    get_circuit_breaker(user_id, :verification).call do
      # Call tween-pay TMCP user resolution endpoint
      begin
        data = make_wallet_request(:get, "/api/v1/tmcp/users/resolve/#{user_id}",
                                    nil, { "Authorization" => "Bearer #{tep_token}" })
        data = data.symbolize_keys

        # Transform response to match jean's expected format
        {
          user_id: data[:user_id] || user_id,
          has_wallet: data.fetch(:has_wallet, true),
          wallet_id: data[:wallet_id],
          verification_level: data[:verification_level] || 0,
          verification_name: data[:verification_name] || "None",
          can_invite: data[:can_invite] || false
        }
      rescue WalletError => e
        if e.code == "WALLET_NOT_FOUND" || e.code == "USER_NOT_FOUND"
          Rails.logger.info "User #{user_id} not found in wallet service (#{e.code}), returning default response"
          # Return default response for non-existent users (allows wallet creation)
          {
            user_id: user_id,
            has_wallet: false,
            wallet_id: nil,
            verification_level: 0,
            verification_name: "None",
            can_invite: true
          }
        else
          # Re-raise other wallet service errors
          raise
        end
      end
    end
  end

  def self.initiate_p2p_transfer(recipient_user_id, amount, currency, tep_token, options = {})
    user_id = extract_user_id_from_tep(tep_token)
    get_circuit_breaker(user_id, :transfers).call do
      request_body = {
        recipient: recipient_user_id,
        amount: amount,
        currency: currency,
        room_id: options[:room_id],
        note: options[:note],
        idempotency_key: options[:idempotency_key]
      }

      response = make_wallet_request(:post, "/api/v1/tmcp/transfers/p2p/initiate",
                                   request_body,
                                   { "Authorization" => "Bearer #{tep_token}" })

      response
    end
  end

  def self.confirm_p2p_transfer(transfer_id, auth_proof, tep_token)
    user_id = extract_user_id_from_tep(tep_token)
    get_circuit_breaker(user_id, :transfers).call do
      request_body = {
        auth_proof: auth_proof
      }

      response = make_wallet_request(:post, "/api/v1/tmcp/transfers/p2p/#{transfer_id}/confirm",
                                   request_body,
                                   { "Authorization" => "Bearer #{tep_token}" })

      response
    end
  end

  def self.accept_p2p_transfer(transfer_id, tep_token)
    user_id = extract_user_id_from_tep(tep_token)
    get_circuit_breaker(user_id, :transfers).call do
      response = make_wallet_request(:post, "/api/v1/tmcp/transfers/p2p/#{transfer_id}/accept",
                                   nil,
                                   { "Authorization" => "Bearer #{tep_token}" })

      response
    end
  end

  def self.reject_p2p_transfer(transfer_id, tep_token = nil, reason = nil)
    user_id = tep_token.present? ? extract_user_id_from_tep(tep_token) : "system"
    get_circuit_breaker(user_id, :transfers).call do
      headers = {}
      if tep_token
        headers["Authorization"] = "Bearer #{tep_token}"
      else
        internal_api_key = ENV.fetch("WALLET_INTERNAL_API_KEY", "")
        headers["X-Internal-API-Key"] = internal_api_key
      end

      body = {}
      body[:reason] = reason if reason

      response = make_wallet_request(:post, "/api/v1/tmcp/transfers/p2p/#{transfer_id}/reject",
                                   body,
                                   headers)

      response
    end
  end

  def self.get_transfer_info(transfer_id)
    # Internal endpoint - use system circuit breaker
    get_circuit_breaker("system", :transfers).call do
      internal_api_key = ENV.fetch("WALLET_INTERNAL_API_KEY", "")

      response = make_wallet_request(:get, "/api/v1/internal/transfers/#{transfer_id}",
                                   nil,
                                   { "X-Internal-API-Key" => internal_api_key })

      response
    end
  end

  def self.create_payment_request(amount, currency, description, tep_token, options = {})
    user_id = extract_user_id_from_tep(tep_token)
    get_circuit_breaker(user_id, :payments).call do
      request_body = {
        amount: amount,
        currency: currency,
        description: description,
        merchant_order_id: options[:merchant_order_id],
        callback_url: options[:callback_url],
        idempotency_key: options[:idempotency_key]
      }

      response = make_wallet_request(:post, "/api/v1/tmcp/payments/request",
                                   request_body,
                                   { "Authorization" => "Bearer #{tep_token}" })

      response
    end
  end

  def self.authorize_payment(payment_id, auth_proof, tep_token)
    user_id = extract_user_id_from_tep(tep_token)
    get_circuit_breaker(user_id, :payments).call do
      request_body = {
        auth_proof: auth_proof
      }

      response = make_wallet_request(:post, "/api/v1/tmcp/payments/#{payment_id}/authorize",
                                   request_body,
                                   { "Authorization" => "Bearer #{tep_token}" })

      response
    end
  end

  # Legacy mock methods for backwards compatibility
  def self.get_verification_status(user_id)
    # Mock verification status (PROTO Section 6.4.2)
    {
      level: 2,
      level_name: "ID Verified",
      verified_at: "2024-01-15T10:00:00Z",
      limits: {
        daily_limit: 100000.00,
        transaction_limit: 50000.00,
        monthly_limit: 500000.00,
        currency: "USD"
      },
      features: {
        p2p_send: true,
        p2p_receive: true,
        miniapp_payments: true
      },
      can_upgrade: true,
      next_level: 3,
      upgrade_requirements: [ "address_proof", "enhanced_id" ]
    }
  end

  # Recursively symbolize keys in a hash
  def self.deep_symbolize_keys(obj)
    case obj
    when Hash
      obj.each_with_object({}) do |(key, value), result|
        result[key.to_sym] = deep_symbolize_keys(value)
      end
    when Array
      obj.map { |item| deep_symbolize_keys(item) }
    else
      obj
    end
  end
end
