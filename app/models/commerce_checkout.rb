class CommerceCheckout < ApplicationRecord
  belongs_to :commerce_cart
  belongs_to :commerce_merchant

  before_validation :assign_checkout_id
  before_validation :assign_expiry

  validates :checkout_id, :buyer_user_id, :expires_at, presence: true
  validates :checkout_id, uniqueness: true
  validates :idempotency_key, uniqueness: { scope: :buyer_user_id }, allow_nil: true
  validates :status, inclusion: { in: %w[created inventory_reserved payment_pending payment_authorized completed expired cancelled failed] }

  def expire!
    update!(status: "expired") if Time.current >= expires_at && !status.in?(%w[completed cancelled failed])
  end

  private
    def assign_checkout_id
      self.checkout_id ||= "chk_#{SecureRandom.alphanumeric(12).downcase}"
    end

    def assign_expiry
      self.expires_at ||= 15.minutes.from_now
    end
end
