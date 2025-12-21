class MfaMethod < ApplicationRecord
  # TMCP Protocol Section 7.4: Multi-Factor Authentication

  belongs_to :user

  # Validations
  validates :user, presence: true
  validates :method_type, presence: true, inclusion: { in: %w[transaction_pin biometric totp] }
  validates :device_id, presence: true
  validates :enabled, inclusion: { in: [ true, false ] }

  # Scopes
  scope :enabled, -> { where(enabled: true) }
  scope :by_type, ->(method_type) { where(method_type: method_type) }
  scope :by_device, ->(device_id) { where(device_id: device_id) }

  # TMCP MFA method types
  METHOD_TYPES = {
    transaction_pin: "transaction_pin",
    biometric: "biometric",
    totp: "totp"
  }.freeze

  # Instance methods
  def transaction_pin?
    method_type == METHOD_TYPES[:transaction_pin]
  end

  def biometric?
    method_type == METHOD_TYPES[:biometric]
  end

  def totp?
    method_type == METHOD_TYPES[:totp]
  end

  def display_name
    case method_type
    when METHOD_TYPES[:transaction_pin]
      "Transaction PIN"
    when METHOD_TYPES[:biometric]
      "Biometric Authentication"
    when METHOD_TYPES[:totp]
      "Authenticator Code"
    else
      method_type.titleize
    end
  end
end
