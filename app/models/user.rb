class User < ApplicationRecord
  # TMCP Protocol Section 4.1: Matrix identity mapping
  enum :status, { active: 0, suspended: 1, deactivated: 2 }, default: :active

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
  validates :matrix_username, presence: true
  validates :matrix_homeserver, presence: true

  # TMCP Protocol: Generate wallet_id if not present
  before_create :generate_wallet_id

  private

  def generate_wallet_id
    self.wallet_id ||= "tw_#{SecureRandom.alphanumeric(12)}"
  end
end
