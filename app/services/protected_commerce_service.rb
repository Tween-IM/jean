# frozen_string_literal: true

# Jean's client for Tween Pay's internal protected-payment API.
#
# Jean is the only caller of these endpoints; requests carry the shared
# internal API key. Every operation is idempotent on the wire, so retries are
# safe. Money movement itself is owned by Tween Pay — Jean never calculates
# available seller funds.
class ProtectedCommerceService
  class Error < StandardError
    attr_reader :code

    def initialize(message, code = nil)
      @code = code
      super(message)
    end
  end

  class ConfigurationError < Error; end

  BASE_URL = ENV.fetch("WALLET_API_BASE_URL", "https://wallet.tween.im")

  # Startup diagnostic: warn if no auth credential is configured.
  _internal_key = ENV["INTERNAL_API_KEY"].presence || ENV["WALLET_INTERNAL_API_KEY"].presence
  if _internal_key.blank?
    Rails.logger.warn(
      "[ProtectedCommerceService] Neither INTERNAL_API_KEY nor WALLET_INTERNAL_API_KEY " \
      "is set. Protected-payment calls to Tween Pay will fail with401. " \
      "Set INTERNAL_API_KEY to the same value as Tween Pay's INTERNAL_API_KEY."
    )
  end

  def self.create_payment(attrs, idempotency_key:)
    post("/api/v1/internal/protected_payments", attrs.merge(idempotency_key: idempotency_key))
  end

  def self.get_payment(protected_payment_id)
    get("/api/v1/internal/protected_payments/#{protected_payment_id}")
  end

  def self.fund(protected_payment_id, actor: "jean")
    post("/api/v1/internal/protected_payments/#{protected_payment_id}/fund", { actor: actor })
  end

  def self.top_up(protected_payment_id, amount_cents:, commission_cents:, seller_proceeds_cents:, actor: "jean")
    post("/api/v1/internal/protected_payments/#{protected_payment_id}/top_up", {
           amount_cents: amount_cents,
           commission_cents: commission_cents,
           seller_proceeds_cents: seller_proceeds_cents,
           actor: actor
         })
  end

  def self.schedule_release(protected_payment_id, release_at:, actor: "system")
    post("/api/v1/internal/protected_payments/#{protected_payment_id}/schedule_release",
         { release_at: release_at, actor: actor })
  end

  def self.cancel_release(protected_payment_id, actor: "system")
    post("/api/v1/internal/protected_payments/#{protected_payment_id}/cancel_release", { actor: actor })
  end

  def self.release(protected_payment_id, actor: "system", trigger: "automatic", amount_cents: nil)
    body = { actor: actor, trigger: trigger }
    body[:amount_cents] = amount_cents if amount_cents
    post("/api/v1/internal/protected_payments/#{protected_payment_id}/release", body)
  end

  def self.refund(protected_payment_id, amount_cents:, reason:, actor: "system")
    post("/api/v1/internal/protected_payments/#{protected_payment_id}/refund",
         { amount_cents: amount_cents, reason: reason, actor: actor })
  end

  def self.open_dispute(protected_payment_id, reason:, actor: "jean")
    post("/api/v1/internal/protected_payments/#{protected_payment_id}/open_dispute",
         { reason: reason, actor: actor })
  end

  def self.resolve_dispute(protected_payment_id, outcome:, seller_amount_cents: 0, buyer_refund_cents: 0,
                           reason:, actor: "operations")
    post("/api/v1/internal/protected_payments/#{protected_payment_id}/resolve_dispute", {
           outcome: outcome,
           seller_amount_cents: seller_amount_cents,
           buyer_refund_cents: buyer_refund_cents,
           reason: reason,
           actor: actor
         })
  end

  def self.get(path)
    request(:get, path)
  end

  def self.post(path, body)
    request(:post, path, body)
  end

  def self.request(method, path, body = nil)
    url = "#{BASE_URL}#{path}"
    headers = {
      "Content-Type" => "application/json",
      "Accept" => "application/json",
      "X-Trace-ID" => SecureRandom.hex(8)
    }
    apply_internal_auth!(headers)

    response = case method
    when :get
                 Faraday.get(url, nil, headers)
    when :post
                 Faraday.post(url, body&.to_json, headers)
    end

    parsed = response.body.present? ? JSON.parse(response.body) : {}

    unless response.success?
      Rails.logger.error("[ProtectedCommerce] ← HTTP #{response.status} #{path}: #{response.body.to_s[0..300]}")
      code = parsed.dig("error", "code")
      message = parsed.dig("error", "message") || "Protected commerce service error (HTTP #{response.status})"
      raise Error.new(message, code)
    end

    parsed.deep_symbolize_keys
  rescue Faraday::Error => e
    raise Error, "Protected commerce service unavailable: #{e.message}"
  rescue JSON::ParserError
    raise Error, "Invalid protected commerce service response"
  end


  def self.apply_internal_auth!(headers)
    # Read at request time so development reloads and rotated credentials do
    # not remain stuck at the value present when Rails booted.
    # INTERNAL_API_KEY is the standard cross-service secret used by both
    # Jean and Tween Pay for server-to-server internal calls.
    api_key = ENV["INTERNAL_API_KEY"].presence || ENV["WALLET_INTERNAL_API_KEY"].presence

    headers["X-Internal-API-Key"] = api_key if api_key
    return headers if api_key

    raise ConfigurationError.new(
      "Protected payments are not configured: set INTERNAL_API_KEY to the same value as Tween Pay's INTERNAL_API_KEY",
      "SERVICE_AUTH_NOT_CONFIGURED"
    )
  end

  private_class_method :apply_internal_auth!
end
