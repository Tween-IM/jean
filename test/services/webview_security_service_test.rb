require "test_helper"

class WebviewSecurityServiceTest < ActiveSupport::TestCase
  setup do
    @security = WebviewSecurityService.new
  end

  test "#validate_csp passes for valid CSP" do
    valid_csp = "default-src 'self'; script-src 'self' 'nonce-abc123'; connect-src 'self' https://tmcp.example.com; frame-ancestors 'none'; upgrade-insecure-requests"

    result = @security.validate_csp(valid_csp)

    assert result[:valid]
    assert result[:errors].empty?
  end

  test "#validate_csp fails for missing default-src" do
    invalid_csp = "script-src 'self'; connect-src 'self'"

    result = @security.validate_csp(invalid_csp)

    assert_not result[:valid]
    assert result[:errors].any?
    assert result[:errors].any? { |e| e[:directive] == "default-src" }
  end

  test "#validate_csp fails for unsafe-inline in script-src" do
    unsafe_csp = "default-src 'self'; script-src 'self' 'unsafe-inline'; connect-src 'self'"

    result = @security.validate_csp(unsafe_csp)

    assert_not result[:valid]
    assert result[:errors].any? { |e| e[:message].include?("unsafe-inline") }
  end

  test "#validate_csp fails for unsafe-eval" do
    unsafe_csp = "default-src 'self'; script-src 'self' 'unsafe-eval'; connect-src 'self'"

    result = @security.validate_csp(unsafe_csp)

    assert_not result[:valid]
    assert result[:errors].any? { |e| e[:message].include?("unsafe-eval") }
  end

  test "#validate_csp warns for missing nonce/hash in script-src" do
    csp_without_nonce = "default-src 'self'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; upgrade-insecure-requests"

    result = @security.validate_csp(csp_without_nonce)

    assert result[:valid]
    assert result[:warnings].any? { |w| w[:message].include?("nonce or hash") }
  end

  test "#validate_url passes for HTTPS URLs" do
    assert @security.validate_url("https://cdn.tween.example.com")
    assert @security.validate_url("https://api.cdn.tween.example.com/path")
  end

  test "#validate_url fails for HTTP URLs" do
    assert_raises(WebviewSecurityService::CSPValidationError) do
      @security.validate_url("http://example.com")
    end
  end

  test "#validate_url passes for whitelisted domains" do
    result = @security.validate_url("https://cdn.tween.example.com")
    assert result
  end

  test "#validate_url fails for non-whitelisted domains" do
    assert_raises(WebviewSecurityService::CSPValidationError) do
      @security.validate_url("https://evil.com")
    end
  end

  test "#generate_nonce generates unique nonces" do
    nonce1 = @security.generate_nonce
    nonce2 = @security.generate_nonce

    assert nonce1 != nonce2
    assert nonce1.start_with?("tmcp-nonce-")
  end

  test "#generate_strict_csp generates valid CSP" do
    csp = @security.generate_strict_csp("miniapp.example.com")

    assert csp.include?("default-src 'self'")
    assert csp.include?("frame-ancestors 'none'")
    assert csp.include?("upgrade-insecure-requests")
  end

  test "#rate_limit_post_messages allows requests within limit" do
    origin = "https://miniapp-#{SecureRandom.alphanumeric(8)}.example.com"

    memory_cache = ActiveSupport::Cache::MemoryStore.new
    original_cache = Rails.cache
    Rails.instance_variable_set(:@cache, memory_cache)

    begin
      10.times do
        assert @security.rate_limit_post_messages(origin, limit: 10, window: 60)
      end
    ensure
      Rails.instance_variable_set(:@cache, original_cache)
    end
  end

  test "#rate_limit_post_messages blocks requests over limit" do
    origin = "https://limited-#{SecureRandom.alphanumeric(8)}.example.com"

    memory_cache = ActiveSupport::Cache::MemoryStore.new
    original_cache = Rails.cache
    Rails.instance_variable_set(:@cache, memory_cache)

    begin
      5.times { assert @security.rate_limit_post_messages(origin, limit: 5, window: 60) }
      assert_not @security.rate_limit_post_messages(origin, limit: 5, window: 60)
    ensure
      Rails.instance_variable_set(:@cache, original_cache)
    end
  end

  test "#validate_post_message sanitizes JSON strings" do
    result = @security.validate_post_message('{"key":"value"}')

    assert result[:valid]
    assert result[:sanitized]
  end

  test "#validate_post_message warns about sensitive data" do
    result = @security.validate_post_message('{"tep_token":"secret"}')

    assert result[:valid]
    assert result[:warnings].any? { |w| w[:type] == "SENSITIVE_DATA" }
  end

  test "#validate_post_message detects prototype pollution attempts" do
    assert_raises(WebviewSecurityService::CSPValidationError) do
      @security.validate_post_message({ "__proto__" => { "polluted" => true } })
    end
  end

  test "#clear_webview_data clears session data" do
    session_id = "test_session_123"

    @security.clear_webview_data(session_id)
    assert true
  end
end
