class MiniAppReviewService
  def self.get_review_status(miniapp)
    {
      app_id: miniapp.app_id,
      name: miniapp.name,
      classification: miniapp.classification,
      status: miniapp.status,
      created_at: miniapp.created_at&.iso8601,
      updated_at: miniapp.updated_at&.iso8601
    }
  end

  def self.run_automated_checks(miniapp)
    results = {
      csp_valid: check_csp_headers(miniapp),
      https_only: check_https_only(miniapp),
      no_credentials: check_no_hardcoded_credentials(miniapp),
      no_obfuscation: check_no_obfuscation(miniapp),
      dependency_scan_passed: run_dependency_scan(miniapp),
      overall_status: :pending
    }

    results[:overall_status] = determine_overall_status(results)

    automated_check = MiniAppAutomatedCheck.create!(
      miniapp_id: miniapp.id,
      status: results[:overall_status],
      csp_valid: results[:csp_valid],
      https_only: results[:https_only],
      no_credentials: results[:no_credentials],
      no_obfuscation: results[:no_obfuscation],
      dependency_scan_passed: results[:dependency_scan_passed],
      raw_results: results
    )

    if results[:overall_status] == :failed
      update_miniapp_status(miniapp, "removed")
    end

    results
  end

  def self.check_csp_headers(miniapp)
    return true if miniapp.classification == "official"

    url = miniapp.manifest["entry_url"]
    return false if url.blank?

    begin
      response = HTTParty.head(url, timeout: 10)
      csp_header = response.headers["Content-Security-Policy"]

      return false if csp_header.blank?

      return false if csp_header.include?("unsafe-inline") || csp_header.include?("unsafe-eval")

      true
    rescue => e
      Rails.logger.warn "CSP check failed for #{miniapp.app_id}: #{e.message}"
      false
    end
  end

  def self.check_https_only(miniapp)
    return true if miniapp.classification == "official"

    urls = [ miniapp.manifest["entry_url"] ] + (miniapp.manifest["redirect_uris"] || [])

    urls.all? { |url| url&.start_with?("https://") }
  end

  def self.check_no_hardcoded_credentials(miniapp)
    return true if miniapp.classification == "official"

    url = miniapp.manifest["entry_url"]
    return true if url.blank?

    patterns = [
      /api[_-]?key['"]?\s*[:=]\s*['"][a-zA-Z0-9]{20,}['"]/i,
      /secret['"]?\s*[:=]\s*['"][a-zA-Z0-9]{20,}['"]/i,
      /password['"]?\s*[:=]\s*['"][^'"]+['"]/i,
      /Bearer\s+[a-zA-Z0-9\-._~+\/]+=*/i
    ]

    begin
      response = HTTParty.get(url, timeout: 10)
      body = response.body

      patterns.none? { |pattern| pattern.match?(body) }
    rescue => e
      Rails.logger.warn "Credential check failed for #{miniapp.app_id}: #{e.message}"
      true
    end
  end

  def self.check_no_obfuscation(miniapp)
    return true if miniapp.classification == "official"

    url = miniapp.manifest["entry_url"]
    return true if url.blank?

    begin
      response = HTTParty.get(url, timeout: 10)
      body = response.body

      return false if body.bytesize > 100_000

      obfuscation_indicators = [
        /\beval\s*\(/,
        /\bFunction\s*\(/,
        /\\x[0-9a-f]{2}/i,
        /\\[ux][0-9a-f]{4}/i,
        /String\.fromCharCode/
      ]

      obfuscation_count = obfuscation_indicators.count { |p| p.match?(body) }
      obfuscation_count < 3
    rescue => e
      Rails.logger.warn "Obfuscation check failed for #{miniapp.app_id}: #{e.message}"
      true
    end
  end

  def self.run_dependency_scan(miniapp)
    return true if miniapp.classification == "official"

    url = miniapp.manifest["entry_url"]
    return true if url.blank?

    begin
      response = HTTParty.get(url, timeout: 10)
      body = response.body

      vulnerable_patterns = [
        /react[\s\S]*?15\./i,
        /lodash[\s\S]*?4\.[0-9]\.[0-9]/i,
        /jquery[\s\S]*?1\.[0-9]\.[0-9]/i
      ]

      vulnerable_patterns.none? { |pattern| pattern.match?(body) }
    rescue => e
      Rails.logger.warn "Dependency scan failed for #{miniapp.app_id}: #{e.message}"
      true
    end
  end

  def self.determine_overall_status(results)
    if results[:csp_valid] && results[:https_only] && results[:no_credentials] &&
       results[:no_obfuscation] && results[:dependency_scan_passed]
      :passed
    else
      :failed
    end
  end

  def self.update_miniapp_status(miniapp, status)
    miniapp.update!(status: status)
  end

  def self.manual_review_pass(miniapp:, reviewer_id: nil, notes: nil)
    miniapp.update!(
      status: "active"
    )

    # Create OAuth application for approved mini-app
    create_oauth_application(miniapp)

    send_approval_notification(miniapp)

    { success: true, status: "active" }
  end

  def self.manual_review_fail(miniapp:, reviewer_id: nil, reason:, notes: nil)
    # MiniApp model doesn't have rejected status, just deactivate it
    miniapp.update!(
      status: "removed"
    )

    # Remove OAuth application if it exists for rejected mini-app
    remove_oauth_application(miniapp)

    send_rejection_notification(miniapp, reason)

    { success: true, status: "removed" }
  end

  def self.send_approval_notification(miniapp)
    Rails.logger.info "Mini-app #{miniapp.app_id} approved"
  end

  def self.send_rejection_notification(miniapp, reason)
    Rails.logger.info "Mini-app #{miniapp.app_id} rejected: #{reason}"
  end

  def self.create_oauth_application(miniapp)
    # Create Doorkeeper OAuth application for the approved mini-app
    oauth_app = Doorkeeper::Application.find_or_create_by!(uid: miniapp.app_id) do |app|
      app.name = miniapp.name
      app.secret = SecureRandom.hex(32)
      app.redirect_uri = miniapp.manifest["redirect_uris"]&.join("\n")
      app.scopes = miniapp.manifest["scopes"]&.join(" ")
      app.confidential = true
    end

    Rails.logger.info "Created OAuth application for mini-app #{miniapp.app_id}: #{oauth_app.uid}"

    oauth_app
  rescue => e
    Rails.logger.error "Failed to create OAuth application for mini-app #{miniapp.app_id}: #{e.message}"
    raise
  end

  def self.remove_oauth_application(miniapp)
    # Remove Doorkeeper OAuth application for rejected mini-app
    oauth_app = Doorkeeper::Application.find_by(uid: miniapp.app_id)
    if oauth_app
      oauth_app.destroy
      Rails.logger.info "Removed OAuth application for rejected mini-app #{miniapp.app_id}"
    end
  rescue => e
    Rails.logger.error "Failed to remove OAuth application for mini-app #{miniapp.app_id}: #{e.message}"
  end
end
