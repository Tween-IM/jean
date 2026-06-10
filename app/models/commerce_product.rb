# frozen_string_literal: true
class CommerceProduct < ApplicationRecord
  belongs_to :commerce_merchant
  belongs_to :commerce_storefront, optional: true
  belongs_to :commerce_category, optional: true, foreign_key: 'category_id'
  has_many :commerce_skus, dependent: :destroy
  has_many :skus, class_name: "CommerceSku", dependent: :destroy
  has_many :commerce_reviews, dependent: :restrict_with_error
  has_many :commerce_product_shipping, dependent: :destroy
  has_many :commerce_shipping_profiles, through: :commerce_product_shipping

  before_validation :assign_product_id

  validates :product_id, :title, presence: true
  validates :product_id, uniqueness: true
  validates :status, inclusion: { in: %w[draft active archived rejected] }
  validates :condition, inclusion: { in: %w[new used refurbished] }
  validates :rating_average, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 5 }, allow_nil: true

  scope :active, -> { where(status: "active") }
  scope :featured, -> { where(featured: true) }
  scope :trending, -> { order(sales_count: :desc, view_count: :desc) }
  scope :with_available_stock, -> {
    joins(:commerce_skus)
      .where.not(commerce_skus: { inventory_status: "out_of_stock" })
      .distinct
  }

  def price_range
    prices = commerce_skus.pluck(:price_cents)
    return nil if prices.empty?

    { min: prices.min, max: prices.max, currency: commerce_skus.first.currency }
  end

  def recache_stats!
    reviews = commerce_reviews.where(status: "approved")
    update!(
      rating_average: reviews.any? ? (reviews.sum(:rating).to_f / reviews.count).round(2) : nil,
      rating_count: reviews.count
    )
  end

  private
    def assign_product_id
      return if product_id.present?

      self.class.uncached do
        10.times do
          candidate = "prod_#{SecureRandom.alphanumeric(12).downcase}"
          unless self.class.exists?(product_id: candidate)
            self.product_id = candidate
            return
          end
        end
      end

      raise "Failed to generate unique product_id after 10 attempts"
    end
end
