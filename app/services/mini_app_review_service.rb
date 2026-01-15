class MiniAppReviewService
  def self.get_review_status(miniapp)
    automated_checks = MiniAppAutomatedCheck.where(miniapp_id: miniapp.miniapp_id).order(created_at: :desc).first

    {
      miniapp_id: miniapp.miniapp_id,
      status: miniapp.status,
      submitted_at: miniapp.submitted_at&.iso8601,
      last_reviewed_at: miniapp.last_reviewed_at&.iso8601,
      automated_review: automated_checks ? {
        status: automated_checks.status,
        completed_at: automated_checks.created_at.iso8601,
        checks: {
          csp_valid: automated_checks.csp_valid,
          https_only: automated_checks.https_only,
          no_hardcoded_credentials: automated_checks.no_credentials,
          no_obfuscated_code: automated_checks.no_obfuscation,
          dependency_scan: automated_checks.dependency_scan_passed
        }
      } : nil,
      manual_review: miniapp.manual_review_notes ? {
        reviewer: miniapp.reviewer_id,
        notes: miniapp.manual_review_notes,
        reviewed_at: miniapp.last_reviewed_at.iso8601
      } : nil,
      rejection_reason: miniapp.rejection_reason
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
      miniapp_id: miniapp.miniapp_id,
      status: results[:overall_status],
      csp_valid: results[:csp_valid],
      https_only: results[:https_only],
      no_credentials: results[:no_credentials],
      no_obfuscation: results[:no_obfuscation],
      dependency_scan_passed: results[:dependency_scan_passed],
      raw_results: results,
      created_at: Time.current
    )

    if results[:overall_status] == :failed
      update_miniapp_status(miniapp, "automated_review_failed")
    end

    results
  end

  def self.check_csp_headers(miniapp)
    return true if miniapp.classification == "official"

    url = miniapp.entry_url
    return false if url.blank?

    begin
      response = HTTParty.head(url, timeout: 10)
      csp_header = response.headers["Content-Security-Policy"]

      return false if csp_header.blank?

      return false if csp_header.include?("unsafe-inline") || csp_header.include?("unsafe-eval")

      true
    rescue => e
      Rails.logger.warn "CSP check failed for #{miniapp.miniapp_id}: #{e.message}"
      false
    end
  end

  def self.check_https_only(miniapp)
    return true if miniapp.classification == "official"

    urls = [ miniapp.entry_url ] + (miniapp.redirect_uris || [])

    urls.all? { |url| url.start_with?("https://") }
  end

  def self.check_no_hardcoded_credentials(miniapp)
    return true if miniapp.classification == "official"

    url = miniapp.entry_url
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
      Rails.logger.warn "Credential check failed for #{miniapp.miniapp_id}: #{e.message}"
      true
    end
  end

  def self.check_no_obfuscation(miniapp)
    return true if miniapp.classification == "official"

    url = miniapp.entry_url
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
      Rails.logger.warn "Obfuscation check failed for #{miniapp.miniapp_id}: #{e.message}"
      true
    end
  end

  def self.run_dependency_scan(miniapp)
    return true if miniapp.classification == "official"

    url = miniapp.entry_url
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
      Rails.logger.warn "Dependency scan failed for #{miniapp.miniapp_id}: #{e.message}"
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
    miniapp.update!(
      status: status,
      updated_at: Time.current
    )
  end

  def self.manual_review_pass(miniapp:, reviewer_id:, notes: nil)
    miniapp.update!(
      status: "active",
      reviewer_id: reviewer_id,
      manual_review_notes: notes,
      last_reviewed_at: Time.current,
      updated_at: Time.current
    )

    # Create OAuth application for approved mini-app
    create_oauth_application(miniapp)

    send_approval_notification(miniapp)

    { success: true, status: "active" }
  end

  def self.manual_review_fail(miniapp:, reviewer_id:, reason:, notes: nil)
    miniapp.update!(
      status: "rejected",
      reviewer_id: reviewer_id,
      manual_review_notes: notes,
      rejection_reason: reason,
      last_reviewed_at: Time.current,
      updated_at: Time.current
    )

    # Remove OAuth application if it exists for rejected mini-app
    remove_oauth_application(miniapp)

    send_rejection_notification(miniapp, reason)

    { success: true, status: "rejected", reason: reason }
  end

  def self.send_approval_notification(miniapp)
    return unless miniapp.webhook_url?

    payload = {
      event: "miniapp_approved",
      miniapp_id: miniapp.miniapp_id,
      status: "approved",
      timestamp: Time.current.iso8601
    }

    signature = WebhookService.sign_payload(payload, miniapp.webhook_secret)

    WebhookService.dispatch(url: miniapp.webhook_url, payload: payload, signature: signature)
  rescue => e
    Rails.logger.error "Failed to send approval notification: #{e.message}"
  end

  def self.send_rejection_notification(miniapp, reason)
    return unless miniapp.webhook_url?

    payload = {
      event: "miniapp_rejected",
      miniapp_id: miniapp.miniapp_id,
      status: "rejected",
      reason: reason,
      timestamp: Time.current.iso8601
    }

    signature = WebhookService.sign_payload(payload, miniapp.webhook_secret)

    WebhookService.dispatch(url: miniapp.webhook_url, payload: payload, signature: signature)
  rescue => e
    Rails.logger.error "Failed to send rejection notification: #{e.message}"
  end

  def self.create_oauth_application(miniapp)
    # Create Doorkeeper OAuth application for the approved mini-app
    oauth_app = Doorkeeper::Application.find_or_create_by!(uid: miniapp.app_id) do |app|
      app.name = miniapp.name
      app.secret = miniapp.client_secret || SecureRandom.hex(32)
      app.redirect_uri = (miniapp.redirect_uris || []).join("\n")
      app.scopes = (miniapp.requested_scopes || []).join(" ")
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
