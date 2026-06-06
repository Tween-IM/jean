# frozen_string_literal: true
class CommerceCart < ApplicationRecord
  belongs_to :commerce_merchant
  has_many :commerce_cart_items, dependent: :destroy
  has_many :items, class_name: "CommerceCartItem", dependent: :destroy

  before_validation :assign_cart_id

  validates :cart_id, :buyer_user_id, :currency, presence: true
  validates :cart_id, uniqueness: true
  validates :status, inclusion: { in: %w[active checked_out abandoned] }

  def recalculate!
    subtotal = commerce_cart_items.sum(:line_total_cents)
    update!(
      subtotal_cents: subtotal,
      total_cents: subtotal + tax_cents + shipping_cents - discount_cents
    )
  end

  private
    def assign_cart_id
      return if cart_id.present?

      loop do
        self.cart_id = "cart_#{SecureRandom.alphanumeric(12).downcase}"
        break unless self.class.exists?(cart_id: cart_id)
      end
    end
end
