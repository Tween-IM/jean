# frozen_string_literal: true
class CommerceCartItem < ApplicationRecord
  belongs_to :commerce_cart
  belongs_to :commerce_sku

  before_validation :copy_price
  after_save -> { commerce_cart.recalculate! }
  after_destroy -> { commerce_cart.recalculate! }

  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price_cents, :line_total_cents, :currency, presence: true
  validates :commerce_sku_id, uniqueness: { scope: :commerce_cart_id }
  validate :sku_available

  private
    def copy_price
      return unless commerce_sku

      self.unit_price_cents = commerce_sku.price_cents
      self.currency = commerce_sku.currency
      self.line_total_cents = unit_price_cents.to_i * quantity.to_i
    end

    def sku_available
      errors.add(:commerce_sku, "is out of stock") if commerce_sku && !commerce_sku.available?(quantity.to_i)
    end
end
