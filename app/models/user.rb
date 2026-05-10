class User < ApplicationRecord
  # TMCP Protocol Section 4.1: Matrix identity mapping
  enum :status, { active: 0, suspended: 1, deactivated: 2 }, default: :active

  # Admin platform roles
  enum :platform_role, {
    none: "none",
    support: "support",
    compliance_officer: "compliance_officer",
    compliance_manager: "compliance_manager",
    operations_analyst: "operations_analyst",
    operations_manager: "operations_manager",
    super_admin: "super_admin"
  }, prefix: :admin, default: :none

  # OAuth applications (Doorkeeper)
  has_many :oauth_applications, class_name: "Doorkeeper::Application", as: :owner

  # Mini-app installations
  has_many :miniapp_installations
  has_many :installed_miniapps, through: :miniapp_installations, source: :miniapp

  # Storage entries for mini-app data
  has_many :storage_entries

  # MFA methods
  has_many :mfa_methods

  # Validations
  validates :matrix_user_id, presence: true, uniqueness: true
  validates :mas_user_id, uniqueness: true, allow_nil: true
  validates :matrix_username, presence: true, format: { with: /.+:.+\..+/, message: "must be in format username:homeserver" }
  validates :matrix_homeserver, presence: true

  # TMCP Protocol: Generate wallet_id if not present
  after_create :generate_wallet_id

  # Admin permission checks
  def platform_admin?
    platform_role != "none"
  end

  def has_admin_permission?(permission)
    return false unless platform_admin?
    return true if admin_super_admin?

    case permission
    when :view_users, :manage_users then admin_super_admin?
    when :view_mini_apps then admin_support? || admin_operations_analyst? || admin_operations_manager? || admin_compliance_officer? || admin_compliance_manager?
    when :manage_mini_apps then admin_operations_manager? || admin_compliance_manager? || admin_super_admin?
    when :view_oauth then admin_operations_manager? || admin_super_admin?
    when :manage_oauth then admin_super_admin?
    when :view_storage then admin_operations_manager? || admin_super_admin?
    when :view_gifts then admin_operations_manager? || admin_super_admin?
    when :view_approvals then admin_compliance_officer? || admin_compliance_manager? || admin_operations_manager?
    when :manage_approvals then admin_compliance_manager? || admin_operations_manager? || admin_super_admin?
    when :view_audit then admin_compliance_manager? || admin_super_admin?
    when :view_settings, :manage_settings then admin_super_admin?
    else false
    end
  end

  private

  def generate_wallet_id
    # Match tween-pay format: tw_#{user.id} where id is database primary key
    if wallet_id.blank?
      update_column(:wallet_id, "tw_#{id}")
    end
  end
end
