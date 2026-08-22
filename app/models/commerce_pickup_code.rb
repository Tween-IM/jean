# frozen_string_literal: true

# A one-time pickup handover challenge. The plaintext code is shown to the
# buyer once at generation and only ever stored hashed (SHA-256). Codes are
# short-lived, single use and confirmed by the seller at handover.
class CommercePickupCode < ApplicationRecord
  class InvalidCodeError < StandardError; end
  class ExpiredCodeError < StandardError; end

  CODE_TTL_MINUTES = 30

  belongs_to :commerce_fulfillment

  before_validation :assign_code_hash

  validates :code_hash, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[active used expired] }

  scope :active, -> { where(status: "active").where("expires_at > ?", Time.current) }

  # Generate a new code, returning the plaintext (shown once).
  def self.issue!(fulfillment, actor: nil)
    plaintext = SecureRandom.base36(6).upcase
    create!(
      commerce_fulfillment: fulfillment,
      code_hash: Digest::SHA256.hexdigest(plaintext),
      status: "active",
      expires_at: CODE_TTL_MINUTES.minutes.from_now
    )
    plaintext
  end

  # Confirm a handover with the plaintext code. Constant-time compare against
  # the stored hash; single use; short expiry.
  def self.confirm!(fulfillment, plaintext, actor: nil)
    code = active.find_by(commerce_fulfillment: fulfillment)
    raise ExpiredCodeError, "no active pickup code" unless code

    expected = Digest::SHA256.hexdigest(plaintext.to_s.strip.upcase)
    unless ActiveSupport::SecurityUtils.secure_compare(code.code_hash, expected)
      raise InvalidCodeError, "pickup code does not match"
    end

    code.update!(status: "used", used_at: Time.current)
    code
  end

  private

  def assign_code_hash
    self.expires_at ||= CODE_TTL_MINUTES.minutes.from_now
    self.status ||= "active"
  end
end
