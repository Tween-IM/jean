class MiniApp < ApplicationRecord
  # TMCP Protocol Section 16: Mini-app classifications
  enum :classification, { official: 0, verified: 1, community: 2, beta: 3 }
  enum :status, { active: 0, deprecated: 1, removed: 2 }

  # Relationships
  has_many :miniapp_installations
  has_many :installed_users, through: :miniapp_installations, source: :user

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
      allowed_scopes = %w[storage_read storage_write user_read public]
      invalid_scopes = scopes - allowed_scopes
      errors.add(:manifest, "community apps can only have: #{allowed_scopes.join(', ')}") if invalid_scopes.any?
    when "beta"
      # Beta apps have sandboxed scopes only
      allowed_scopes = %w[storage_read storage_write public]
      invalid_scopes = scopes - allowed_scopes
      errors.add(:manifest, "beta apps can only have: #{allowed_scopes.join(', ')}") if invalid_scopes.any?
    end
  end

  def validate_manifest_structure
    return unless manifest.present?

    required_keys = %w[permissions scopes]
    missing_keys = required_keys - manifest.keys
    errors.add(:manifest, "missing required keys: #{missing_keys.join(', ')}") if missing_keys.any?
  end
end
