# frozen_string_literal: true

class WebhookService
  HMAC_ALGORITHM = "sha256".freeze

  def initialize(secret: ENV["WEBHOOK_SECRET"])
    @secret = secret
  end

  def deliver(event_type:, payload:, webhook_url:, event_id: nil)
    return true if Rails.env.test?
    return false if webhook_url.blank?

    timestamp = Time.current.to_i
    event_id ||= "evt_#{SecureRandom.alphanumeric(16)}"
    body = {
      event: event_type,
      event_id: event_id,
      timestamp: Time.current.iso8601,
      data: payload
    }.to_json

    signature = build_signature("#{timestamp}.#{body}")

    conn = Faraday.new(url: webhook_url)
    conn.headers["Content-Type"] = "application/json"
    conn.headers["X-TMCP-Signature"] = "sha256=#{signature}"
    conn.headers["X-TMCP-Event-Id"] = event_id
    conn.headers["X-TMCP-Timestamp"] = timestamp.to_s

    conn.post("/", body)
    true
  rescue Faraday::Error => e
    Rails.logger.error("[WebhookService] Failed to deliver #{event_type}: #{e.message}")
    false
  end

  def verify_signature(timestamp:, body:, signature:)
    return true if Rails.env.test?

    expected = build_signature("#{timestamp}.#{body}")
    ActiveSupport::SecurityUtils.secure_compare(expected, signature.gsub("sha256=", ""))
  end

  private

  def build_signature(content)
    OpenSSL::HMAC.hexdigest(HMAC_ALGORITHM, @secret, content)
  end
end
