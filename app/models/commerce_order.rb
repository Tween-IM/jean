# frozen_string_literal: true
class CommerceOrder < ApplicationRecord
  belongs_to :commerce_merchant
  has_many :commerce_order_items, dependent: :destroy
  has_many :items, class_name: "CommerceOrderItem", dependent: :destroy

  before_validation :assign_order_id

  validates :order_id, :buyer_user_id, :payment_id, :currency, presence: true
  validates :order_id, uniqueness: true
  validates :status, inclusion: { in: %w[pending_payment paid processing fulfilled cancelled refunded partially_refunded] }
  validates :fulfillment_status, inclusion: { in: %w[not_required unfulfilled partially_fulfilled fulfilled failed] }

  def shipping_address
    {
      line1: shipping_address_line1,
      line2: shipping_address_line2,
      city: shipping_city,
      state: shipping_state,
      postal_code: shipping_postal_code,
      country: shipping_country,
      phone: shipping_phone
    }.compact
  end

  private
    def assign_order_id
      return if order_id.present?

      loop do
        self.order_id = "ord_#{SecureRandom.alphanumeric(12).downcase}"
        break unless self.class.exists?(order_id: order_id)
      end
    end
end
