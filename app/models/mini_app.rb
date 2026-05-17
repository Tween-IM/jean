class MiniApp < ApplicationRecord
  # TMCP Protocol Section 16: Mini-app classifications
  enum :classification, { official: 0, verified: 1, community: 2, beta: 3 }
  enum :status, { pending_review: 0, under_review: 1, approved: 2, active: 3, rejected: 4, appeal_submitted: 5, deprecated: 6, removed: 7, changes_requested: 8 }

  # Client type: public, confidential, or hybrid
  validates :client_type, presence: true, inclusion: { in: %w[public confidential hybrid], message: "must be public, confidential, or hybrid" }

  # Relationships
  has_many :miniapp_installations, foreign_key: :mini_app_id
  has_many :installed_users, through: :miniapp_installations, source: :user
  has_many :mini_app_automated_checks, foreign_key: :miniapp_id
  has_many :mini_app_appeals, foreign_key: :miniapp_id

  # Validations
  validates :app_id, presence: true, uniqueness: true,
            format: { with: /\Ama_[a-zA-Z0-9]+\z/, message: "must start with 'ma_' followed by alphanumeric characters" }
  validates :name, presence: true
  validates :version, presence: true
  validates :classification, presence: true

  # TMCP Protocol Section 16: Scope validation
  validate :validate_scopes_for_classification

  # JSON validation for manifest
  validates :manifest, presence: true
  validate :validate_manifest_structure

  # Scopes
  scope :pending_review, -> { where(status: :pending_review) }
  scope :under_review, -> { where(status: :under_review) }
  scope :approved, -> { where(status: :approved) }
  scope :active, -> { where(status: :active) }
  scope :rejected, -> { where(status: :rejected) }
  scope :appeals_pending, -> { where(status: :appeal_submitted) }
  scope :changes_requested, -> { where(status: :changes_requested) }

  # Review workflow methods
  def submit_for_review!
    update!(status: :under_review, submitted_at: Time.current)
  end

  def approve!(reviewer_id:, notes: nil)
    update!(
      status: :approved,
      reviewer_id: reviewer_id,
      reviewed_at: Time.current
    )
    MiniAppReviewService.create_oauth_application(self)
  end

  def reject!(reviewer_id:, reason:, notes: nil)
    update!(
      status: :rejected,
      rejection_reason: reason,
      reviewer_id: reviewer_id,
      reviewed_at: Time.current
    )
  end

  def request_changes!(reviewer_id:, reason:)
    update!(
      status: :changes_requested,
      revision_request: reason,
      revision_requested_at: Time.current,
      reviewer_id: reviewer_id
    )
  end

  def activate!
    update!(status: :active)
  end

  def deprecate!
    update!(status: :deprecated)
  end

  # Helper methods for admin
  def latest_automated_check
    mini_app_automated_checks.order(created_at: :desc).first
  end

  def pending_appeals
    mini_app_appeals.where(status: :pending_review)
  end

  def installation_count
    miniapp_installations.count
  end

  def status_label
    status.to_s.humanize.titleize
  end

  def classification_label
    classification.to_s.humanize.titleize
  end

  def can_submit_for_review?
    status == :pending_review
  end

  def can_approve?
    status == :under_review
  end

  def can_reject?
    status == :under_review
  end

  def can_appeal?
    status == :rejected
  end

  def awaiting_review?
    status == :under_review
  end

  def needs_attention?
    pending_review? || under_review? || appeal_submitted?
  end

  private

  def validate_scopes_for_classification
    return unless manifest.present?

    scopes = manifest["scopes"] || []
    case classification
    when "official"
      # Official apps can have all scopes including privileged
    when "verified"
      # Verified apps can have standard scopes
      privileged_scopes = scopes.select { |s| s.start_with?("privileged") }
      errors.add(:manifest, "verified apps cannot have privileged scopes") if privileged_scopes.any?
    when "community"
      # Community apps have limited scopes
      allowed_scopes = %w[storage:read storage:write user:read public]
      invalid_scopes = scopes - allowed_scopes
      errors.add(:manifest, "community apps can only have: #{allowed_scopes.join(', ')}") if invalid_scopes.any?
    when "beta"
      # Beta apps have sandboxed scopes only
      allowed_scopes = %w[storage:read storage:write public]
      invalid_scopes = scopes - allowed_scopes
      errors.add(:manifest, "beta apps can only have: #{allowed_scopes.join(', ')}") if invalid_scopes.any?
    end
  end

  def validate_manifest_structure
    return unless manifest.present?

    unless manifest.key?("scopes") && manifest["scopes"].is_a?(Array) && manifest["scopes"].any?
      errors.add(:manifest, "missing required key: scopes (must be an array of scope strings like 'user:read')")
    end
  end
end