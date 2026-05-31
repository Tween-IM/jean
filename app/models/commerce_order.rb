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

  private
    def assign_order_id
      self.order_id ||= "ord_#{SecureRandom.alphanumeric(12).downcase}"
    end
end
