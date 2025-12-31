class WebhookSecurityService
  MAX_TIMESTAMP_AGE = 300
  IDEMPOTENCY_TTL = 86400

  class SignatureError < StandardError
    attr_reader :code

    def initialize(code, message)
      super(message)
      @code = code
    end
  end

  def verify_signature(payload, signature, secret)
    expected = compute_hmac_sha256(payload, secret)

    return false unless expected.present? && signature.present?

    secure_compare(expected, signature)
  end

  def compute_hmac_sha256(payload, secret)
    if payload.is_a?(Hash) || payload.is_a?(Array)
      payload = payload.to_json
    end

    OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, payload)
  end

  def validate_timestamp(timestamp, max_age = MAX_TIMESTAMP_AGE)
    timestamp_int = timestamp.to_i

    if timestamp_int == 0
      raise SignatureError.new(
        "INVALID_TIMESTAMP",
        "Invalid timestamp format"
      )
    end

    age = Time.current.to_i - timestamp_int

    if age > max_age
      raise SignatureError.new(
        "EXPIRED_TIMESTAMP",
        "Webhook timestamp is too old (#{age}s > #{max_age}s)"
      )
    end

    if age < -max_age
      raise SignatureError.new(
        "FUTURE_TIMESTAMP",
        "Webhook timestamp is in the future"
      )
    end

    true
  end

  def validate_idempotency_key(idempotency_key, wallet_id = nil)
    cache_key = build_idempotency_key(idempotency_key, wallet_id)

    existing = Rails.cache.read(cache_key)

    if existing
      return {
        duplicate: true,
        original_response: existing,
        message: "Duplicate request - returning cached response"
      }
    end

    nil
  end

  def store_idempotent_response(idempotency_key, response, wallet_id = nil)
    cache_key = build_idempotency_key(idempotency_key, wallet_id)
    Rails.cache.write(cache_key, response, expires_in: IDEMPOTENCY_TTL)
    response
  end

  def validate_callback_source(source_ip, allowed_ips = nil)
    return true if allowed_ips.blank?

    Array(allowed_ips).each do |ip|
      if match_ip?(source_ip, ip)
        return true
      end
    end

    raise SignatureError.new(
      "UNAUTHORIZED_SOURCE",
      "Callback source IP not in allowed list"
    )
  end

  def sanitize_webhook_payload(payload)
    sanitized = {}

    payload.each do |key, value|
      sanitized_key = sanitize_key(key)
      next if sanitized_key.nil?

      sanitized_value = case value
      when Hash
        sanitize_webhook_payload(value)
      when Array
        value.map { |v| v.is_a?(Hash) ? sanitize_webhook_payload(v) : v }
      when String
        sanitize_string(value)
      else
        value
      end

      sanitized[sanitized_key] = sanitized_value
    end

    sanitized
  end

  def build_webhook_signature_headers(payload, secret)
    timestamp = Time.current.to_i
    payload_string = payload.to_json

    signature = compute_hmac_sha256("#{timestamp}.#{payload_string}", secret)

    {
      "X-TMCP-Timestamp": timestamp.to_s,
      "X-TMCP-Signature": signature,
      "X-TMCP-Version": "1.5.0"
    }
  end

  def verify_webhook_request(request)
    signature = request.headers["X-TMCP-Signature"]
    timestamp = request.headers["X-TMCP-Timestamp"]
    payload = request.raw_post || request.body.read

    errors = []

    unless signature.present?
      errors << {
        code: "MISSING_SIGNATURE",
        message: "Missing X-TMCP-Signature header"
      }
    end

    unless timestamp.present?
      errors << {
        code: "MISSING_TIMESTAMP",
        message: "Missing X-TMCP-Timestamp header"
      }
    end

    return { valid: false, errors: errors } if errors.any?

    begin
      validate_timestamp(timestamp)
    rescue SignatureError => e
      errors << { code: e.code, message: e.message }
    end

    return { valid: false, errors: errors } if errors.any?

    begin
      valid = verify_signature(payload, signature, webhook_secret)
      unless valid
        errors << {
          code: "INVALID_SIGNATURE",
          message: "Webhook signature verification failed"
        }
      end
    rescue => e
      errors << {
        code: "SIGNATURE_ERROR",
        message: e.message
      }
    end

    {
      valid: errors.empty?,
      errors: errors,
      timestamp_validated: true,
      signature_validated: errors.empty?
    }
  end

  private

  def webhook_secret
    @webhook_secret ||= ENV["TMCP_WEBHOOK_SECRET"] || Rails.application.config.tmcp[:hmac_secret]
  end

  def build_idempotency_key(key, wallet_id)
    base = "webhook_idempotency:#{key}"
    wallet_id ? "#{base}:#{wallet_id}" : base
  end

  def match_ip?(client_ip, allowed_ip)
    if allowed_ip.include?("/")
      IPAddr.new(allowed_ip).include?(client_ip)
    else
      client_ip == allowed_ip
    end
  rescue IPAddr::InvalidAddressError
    false
  end

  def sanitize_key(key)
    return nil if key.to_s.include?("__proto__")
    return nil if key.to_s.include?("constructor")
    return nil if key.to_s.include?("prototype")

    key.to_s.gsub(/[^\w\-]/, "_").to_sym
  end

  def sanitize_string(value)
    return value unless value.is_a?(String)

    if value.length > 1_000_000
      value[0..1_000_000] + "... (truncated)"
    else
      value
    end
  end

  def secure_compare(a, b)
    return false unless a.bytesize == b.bytesize

    a.bytes.zip(b.bytes).all? { |x, y| x == y }
  rescue => e
    Rails.logger.error "Secure compare error: #{e.message}"
    false
  end
end
