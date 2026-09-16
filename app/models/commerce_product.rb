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
  validates :store_type, inclusion: { in: %w[marketplace ecommerce] }, allow_nil: true
  validates :rating_average, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 5 }, allow_nil: true

  # Who the source says made a listing and who supplies it.
  #
  # Both were published on every listing and only readable out of
  # `source_payload`: the brand is the make ("Nokia"), the supplier is the
  # seller that fulfils it ("Kriscrown global links"). Neither is the merchant
  # that sells to the buyer — for imported goods that is always the platform's
  # own importer — so the storefront stays the shelf, the merchant stays the
  # seller of record, and the supplier is the party to actually buy from.
  def source_identity
    payload = source_payload.is_a?(Hash) ? source_payload : {}
    seller = payload["seller"].is_a?(Hash) ? payload["seller"] : {}

    {
      brand: payload["brand"].to_s.strip.presence,
      supplier_name: (seller["name"].presence || payload["seller_name"]).to_s.strip.presence,
      supplier_id: (seller["id"].presence || payload["seller_id"]).to_s.strip.presence,
      supplier_platform: source_platform.presence,
      supplier_url: source_url.presence,
      source_price_cents: payload["price_cents"].presence&.to_i
    }
  end

  # Fills what the source published and overwrites nothing: a re-import that
  # arrives without a seller must not erase the one we already knew.
  def apply_source_identity!
    source_identity.each do |attribute, value|
      next if value.blank?

      public_send("#{attribute}=", value)
    end

    save! if changed?
  end

  scope :active, -> { where(status: "active") }
  scope :featured, -> { where(featured: true) }
  scope :trending, -> { order(sales_count: :desc, view_count: :desc) }

  # Listings mirrored from an external marketplace (Jumia, Konga, ...) by the
  # scraper/importer. Provenance lives in the source_* columns.
  scope :imported, -> { where.not(source_platform: nil) }
  scope :with_available_stock, -> {
    joins(:commerce_skus)
      .where.not(commerce_skus: { inventory_status: "out_of_stock" })
      .distinct
  }

  # Effective experience type. A product attached to a storefront inherits the
  # store's type; a standalone product is always a marketplace listing.
  def effective_store_type
    store_type.presence || commerce_storefront&.store_type || "marketplace"
  end

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
