class MiniAppReviewService
  REVIEW_TYPES = %w[automated manual business].freeze
  CLASSIFICATION_TYPES = %w[official verified community beta].freeze

  class ReviewError < StandardError
    attr_reader :code

    def initialize(code, message)
      super(message)
      @code = code
    end
  end

  def submit_for_review(miniapp_id)
    miniapp = MiniApp.find_by(app_id: miniapp_id)

    raise ReviewError.new("NOT_FOUND", "Mini-app not found") unless miniapp

    if miniapp.status != "pending_review"
      raise ReviewError.new(
        "INVALID_STATE",
        "Mini-app must be in pending_review state to submit"
      )
    end

    automated_result = run_automated_checks(miniapp)

    review = MiniAppReview.create!(
      miniapp_id: miniapp_id,
      status: automated_result[:passes] ? "pending_manual_review" : "failed",
      automated_checks: automated_result,
      submitted_at: Time.current
    )

    if automated_result[:passes]
      miniapp.update!(status: "under_review")
    else
      miniapp.update!(status: "rejected", rejection_reason: "Automated checks failed")
    end

    review
  end

  def run_automated_checks(miniapp)
    checks = {
      csp_valid: check_csp(miniapp),
      https_only: check_https_only(miniapp),
      no_credentials: check_no_credentials(miniapp),
      no_obfuscation: check_no_obfuscation(miniapp),
      dependencies_clean: check_dependencies(miniapp)
    }

    passed = checks.values.all? { |c| c[:passed] }

    {
      passes: passed,
      status: passed ? "automated_review_complete" : "automated_review_failed",
      checks: checks,
      completed_at: Time.current.iso8601
    }
  end

  def check_csp(miniapp)
    csp = miniapp.manifest["csp"] || ""

    result = WebviewSecurityService.new.validate_csp(csp, miniapp.app_id)

    {
      passed: result[:valid],
      csp: csp,
      errors: result[:errors],
      warnings: result[:warnings]
    }
  end

  def check_https_only(miniapp)
    entry_url = miniapp.manifest["entry_url"]

    uri = URI.parse(entry_url) rescue nil

    {
      passed: uri&.scheme == "https",
      entry_url: entry_url,
      message: uri&.scheme == "https" ? "All resources loaded over HTTPS" : "Insecure resource loading detected"
    }
  end

  def check_no_credentials(miniapp)
    manifest_json = miniapp.to_json

    has_creds = manifest_json.match?(/("api_key|access_token|client_secret|password|bearer_token)["\s]*[:=]/i)

    {
      passed: !has_creds,
      message: has_creds ? "Potential hardcoded credentials detected" : "No hardcoded credentials found"
    }
  end

  def check_no_obfuscation(miniapp)
    manifest_json = miniapp.to_json

    suspicious_patterns = [
      /\beval\s*\(/i,
      /\bFunction\s*\(/,
      /\\x[0-9a-f]{2}/i,
      /u003c/u,
      /obfuscate/i,
      /packer/i
    ]

    found_patterns = suspicious_patterns.select { |p| manifest_json.match?(p) }

    {
      passed: found_patterns.empty?,
      patterns: found_patterns.map(&:source),
      message: found_patterns.empty? ? "Code appears clean" : "Potentially obfuscated code detected"
    }
  end

  def check_dependencies(miniapp)
    {
      passed: true,
      message: "Dependency check skipped (would integrate with vulnerability scanner)"
    }
  end

  def assign_reviewer(review_id, reviewer_id)
    review = MiniAppReview.find(review_id)

    review.update!(
      reviewer_id: reviewer_id,
      status: "under_review",
      manual_review_started_at: Time.current
    )

    review
  end

  def complete_manual_review(review_id, result, notes = {})
    review = MiniAppReview.find(review_id)

    review.update!(
      status: result[:approved] ? "approved" : "rejected",
      manual_review_result: result,
      manual_review_notes: notes,
      completed_at: Time.current,
      reviewer_id: result[:reviewer_id]
    )

    miniapp = MiniApp.find_by(app_id: review.miniapp_id)
    miniapp.update!(
      status: result[:approved] ? "approved" : "rejected",
      classification: result[:classification] || miniapp.classification
    )

    review
  end

  def submit_appeal(miniapp_id, reason, changes, evidence = [])
    miniapp = MiniApp.find_by(app_id: miniapp_id)

    raise ReviewError.new("NOT_FOUND", "Mini-app not found") unless miniapp

    unless miniapp.status == "rejected"
      raise ReviewError.new(
        "INVALID_STATE",
        "Only rejected mini-apps can be appealed"
      )
    end

    appeal = MiniAppAppeal.create!(
      miniapp_id: miniapp_id,
      original_review_id: miniapp.last_review_id,
      reason: reason,
      changes_made: changes,
      evidence: evidence,
      status: "under_review"
    )

    miniapp.update!(status: "under_review", last_appeal_id: appeal.id)

    appeal
  end

  def estimate_review_timeline(miniapp)
    case miniapp.classification
    when "official"
      { automated: "instant", manual: "N/A", total: "instant" }
    when "verified"
      { automated: "1 hour", manual: "2-5 days", total: "2-5 days" }
    when "community"
      { automated: "1 hour", manual: "5-10 days", total: "5-10 days" }
    when "beta"
      { automated: "1 hour", manual: "priority", total: "1-2 days" }
    else
      { automated: "1 hour", manual: "5-10 days", total: "5-10 days" }
    end
  end
end
