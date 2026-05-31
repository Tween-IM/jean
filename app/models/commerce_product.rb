# frozen_string_literal: true
class CommerceProduct < ApplicationRecord
  belongs_to :commerce_merchant
  belongs_to :commerce_storefront, optional: true
  has_many :commerce_skus, dependent: :destroy
  has_many :skus, class_name: "CommerceSku", dependent: :destroy

  before_validation :assign_product_id

  validates :product_id, :title, presence: true
  validates :product_id, uniqueness: true
  validates :status, inclusion: { in: %w[draft active archived rejected] }

  scope :active, -> { where(status: "active") }

  def price_range
    prices = commerce_skus.pluck(:price_cents)
    return nil if prices.empty?

    { min: prices.min, max: prices.max, currency: commerce_skus.first.currency }
  end

  private
    def assign_product_id
      self.product_id ||= "prod_#{SecureRandom.alphanumeric(12).downcase}"
    end
end
