class WebhookService
  def self.verify_signature(payload, signature, secret)
    security_service = WebhookSecurityService.new
    security_service.verify_signature(payload, signature, secret)
  end

  def self.sign_payload(payload, secret)
    security_service = WebhookSecurityService.new
    security_service.compute_hmac_sha256(payload, secret)
  end

  def self.dispatch(url:, payload:, signature:)
    require "net/http"
    require "uri"

    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["X-TMCP-Signature"] = signature
    request.body = payload.to_json

    begin
      response = http.request(request)
      Rails.logger.info "Webhook dispatched to #{url}: #{response.code}"
      { success: response.code.to_i == 200, status: response.code, response: response.body }
    rescue => e
      Rails.logger.error "Webhook dispatch failed: #{e.message}"
      { success: false, error: e.message }
    end
  end
end
