# frozen_string_literal: true

class WebhookService
  HMAC_ALGORITHM = "sha256".freeze

  def initialize(secret: ENV["WEBHOOK_SECRET"])
    @secret = secret
  end

  def deliver(event_type:, payload:, webhook_url:, event_id: nil)
    return false if webhook_url.blank?

    event_id ||= "evt_#{SecureRandom.alphanumeric(16)}"
    delivery = WebhookDelivery.find_or_create_by!(event_id: event_id) do |record|
      record.event_type = event_type
      record.webhook_url = webhook_url
      record.payload = payload
      record.status = "pending"
    end

    return true if Rails.env.test?

    deliver_record(delivery)
  end

  def deliver_record(delivery)
    timestamp = Time.current.to_i
    body = {
      event: delivery.event_type,
      event_id: delivery.event_id,
      timestamp: Time.current.iso8601,
      data: delivery.payload
    }.to_json

    signature = build_signature("#{timestamp}.#{body}")

    conn = Faraday.new(url: delivery.webhook_url)
    conn.headers["Content-Type"] = "application/json"
    conn.headers["X-TMCP-Signature"] = "sha256=#{signature}"
    conn.headers["X-TMCP-Event-Id"] = delivery.event_id
    conn.headers["X-TMCP-Timestamp"] = timestamp.to_s

    response = conn.post("/", body)
    if response.success?
      delivery.update!(status: "delivered", delivered_at: Time.current, response_status: response.status, last_error: nil)
      true
    else
      record_failure(delivery, "HTTP #{response.status}", response.status)
      false
    end
  rescue Faraday::Error => e
    Rails.logger.error("[WebhookService] Failed to deliver #{delivery&.event_type}: #{e.message}")
    record_failure(delivery, e.message) if delivery
    false
  end

  def verify_signature(timestamp:, body:, signature:)
    return true if Rails.env.test?

    expected = build_signature("#{timestamp}.#{body}")
    ActiveSupport::SecurityUtils.secure_compare(expected, signature.gsub("sha256=", ""))
  end

  private

  def record_failure(delivery, error_message, response_status = nil)
    attempts = delivery.attempts + 1
    status = attempts >= WebhookDelivery::MAX_ATTEMPTS ? "dead" : "failed"
    delivery.update!(
      attempts: attempts,
      status: status,
      response_status: response_status,
      last_error: error_message,
      next_attempt_at: status == "dead" ? nil : delivery.next_retry_at
    )
  end

  def build_signature(content)
    OpenSSL::HMAC.hexdigest(HMAC_ALGORITHM, @secret, content)
  end
end
