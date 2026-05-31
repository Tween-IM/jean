# frozen_string_literal: true
class CommerceOrderItem < ApplicationRecord
  belongs_to :commerce_order

  validates :sku_id, :product_id, :title, :currency, presence: true
  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price_cents, :line_total_cents, numericality: { greater_than_or_equal_to: 0 }
end
