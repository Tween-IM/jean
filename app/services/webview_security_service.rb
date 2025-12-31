class WebviewSecurityService
  class CSPValidationError < StandardError
    attr_reader :code, :details

    def initialize(code, message, details = {})
      super(message)
      @code = code
      @details = details
    end
  end

  REQUIRED_CSP_DIRECTIVES = %w[
    default-src
    script-src
    connect-src
    frame-ancestors
    upgrade-insecure-requests
  ].freeze

  DISALLOWED_KEYWORDS = %w[
    'unsafe-inline'
    'unsafe-eval'
    http:
    data:
  ].freeze

  RECOMMENDED_DIRECTIVES = %w[
    img-src
    style-src
    font-src
    media-src
    object-src
  ].freeze

  WHITELISTED_DOMAINS = %w[
    https://cdn.tween.example.com
    https://tmcp.example.com
  ].freeze

  def validate_csp(csp_string, miniapp_id: nil)
    return { valid: true, warnings: [] } if csp_string.blank?

    directives = parse_csp(csp_string)

    errors = []
    warnings = []

    REQUIRED_CSP_DIRECTIVES.each do |directive|
      unless directives.key?(directive)
        errors << {
          directive: directive,
          message: "Missing required CSP directive: #{directive}"
        }
      end
    end

    directives.each do |directive, values|
      values.each do |value|
        DISALLOWED_KEYWORDS.each do |keyword|
          if value.include?(keyword)
            if keyword == "'unsafe-inline'" || keyword == "'unsafe-eval'"
              errors << {
                directive: directive,
                value: value,
                message: "Disallowed keyword '#{keyword}' in #{directive}"
              }
            elsif keyword == "http:" && directive != "frame-ancestors"
              warnings << {
                directive: directive,
                value: value,
                message: "HTTP source '#{keyword}' may cause mixed content issues"
              }
            elsif keyword == "data:"
              warnings << {
                directive: directive,
                value: value,
                message: "Data URIs may pose security risks"
              }
            end
          end
        end
      end
    end

    if directives["script-src"] && !directives["script-src"].any? { |v| v.include?("'nonce-") || v.include?("'sha256-") }
      warnings << {
        directive: "script-src",
        message: "script-src does not use nonce or hash-based source validation"
      }
    end

    {
      valid: errors.empty?,
      errors: errors,
      warnings: warnings,
      directives: directives
    }
  end

  def validate_url(url, allowed_domains: [])
    uri = URI.parse(url)

    unless uri.scheme == "https"
      raise CSPValidationError.new(
        "INSECURE_SCHEME",
        "URL must use HTTPS",
        url: url, scheme: uri.scheme
      )
    end

    allowed = allowed_domains + WHITELISTED_DOMAINS
    domain_matches = allowed.any? do |domain|
      domain_uri = URI.parse(domain)
      uri.host == domain_uri.host || uri.host.end_with?(".#{domain_uri.host}")
    end

    unless domain_matches
      raise CSPValidationError.new(
        "DOMAIN_NOT_WHITELISTED",
        "URL domain is not in whitelist",
        url: url, allowed_domains: allowed
      )
    end

    true
  end

  def validate_post_message(message, expected_origin: nil)
    result = {
      valid: true,
      warnings: [],
      sanitized: false
    }

    if message.is_a?(String)
      begin
        parsed = JSON.parse(message)
        result[:sanitized] = true if parsed != message
        message = parsed
      rescue JSON::ParserError
      end
    end

    if message.is_a?(Hash)
      if message.key?("tep_token") || message.key?("access_token")
        result[:warnings] << {
          type: "SENSITIVE_DATA",
          message: "Message contains potentially sensitive token data"
        }
      end

      message.each_key do |key|
        if key.to_s.include?("__proto__") || key.to_s.include?("constructor")
          raise CSPValidationError.new(
            "PROTOTYPE_POLLUTION",
            "Potential prototype pollution attempt detected"
          )
        end
      end
    end

    result
  end

  def generate_nonce
    @nonce_counter ||= 0
    @nonce_counter += 1
    "tmcp-nonce-#{@nonce_counter}-#{SecureRandom.alphanumeric(8)}"
  end

  def generate_strict_csp(miniapp_domain = nil)
    csp = {
      "default-src" => [ "'self'" ],
      "script-src" => [ "'self'", "'nonce-#{generate_nonce}'" ],
      "connect-src" => [ "'self'", "https://tmcp.example.com" ],
      "frame-ancestors" => [ "'none'" ],
      "upgrade-insecure-requests" => []
    }

    if miniapp_domain
      csp["connect-src"] << "https://#{miniapp_domain}"
    end

    csp.map { |directive, values| "#{directive} #{values.join(' ')}" }.join("; ")
  end

  def rate_limit_post_messages(origin, limit: 100, window: 60)
    key = "postmessage_rate:#{origin.gsub(/[^a-zA-Z0-9]/, '_')}"
    current = Rails.cache.read(key) || 0

    if current >= limit
      return false
    end

    Rails.cache.write(key, current + 1, expires_in: window.seconds)
    true
  end

  def clear_webview_data(session_id)
    cache_keys = Rails.cache.instance_variable_get(:@data)&.keys || []
    cache_keys.each do |key|
      if key.start_with?("webview_data:#{session_id}:")
        Rails.cache.delete(key)
      end
    end
    true
  end

  private

  def parse_csp(csp_string)
    directives = {}

    csp_string.split(";").each do |part|
      parts = part.strip.split(/\s+/)
      next if parts.empty?

      directive = parts[0]
      values = parts[1..] || []

      directives[directive] ||= []
      directives[directive] += values
    end

    directives
  end
end
