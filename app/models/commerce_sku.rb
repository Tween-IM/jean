# frozen_string_literal: true
class CommerceSku < ApplicationRecord
  belongs_to :commerce_product
  has_many :commerce_cart_items, dependent: :restrict_with_error
  has_many :cart_items, class_name: "CommerceCartItem", dependent: :restrict_with_error

  before_validation :assign_sku_id

  validates :sku_id, :price_cents, :currency, presence: true
  validates :sku_id, uniqueness: true
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :quantity_available, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :inventory_status, inclusion: { in: %w[in_stock low_stock out_of_stock preorder] }

  def available?(quantity = 1)
    return false if inventory_status == "out_of_stock"
    return true if quantity_available.nil?

    quantity_available >= quantity
  end

  private
    def assign_sku_id
      return if sku_id.present?

      self.class.uncached do
        10.times do
          candidate = "sku_#{SecureRandom.alphanumeric(12).downcase}"
          unless self.class.exists?(sku_id: candidate)
            self.sku_id = candidate
            return
          end
        end
      end

      raise "Failed to generate unique sku_id after 10 attempts"
    end
end
