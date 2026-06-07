# frozen_string_literal: true
class CommerceStorefront < ApplicationRecord
  belongs_to :commerce_merchant
  has_many :commerce_products, dependent: :nullify
  has_many :products, class_name: "CommerceProduct", dependent: :nullify
  has_many :commerce_reviews, dependent: :restrict_with_error

  before_validation :assign_storefront_id
  before_validation :assign_slug
  before_validation :assign_store_url_slug

  validates :storefront_id, :slug, :display_name, presence: true
  validates :storefront_id, uniqueness: true
  validates :slug, uniqueness: { scope: :commerce_merchant_id }
  validates :store_url_slug, uniqueness: true, allow_blank: true
  validates :status, inclusion: { in: %w[draft published suspended closed] }
  validates :accent_color, format: { with: /\A#[0-9A-Fa-f]{6}\z/, message: "must be a valid hex color" }, allow_blank: true

  scope :published, -> { where(status: "published") }
  scope :featured, -> { where(featured: true) }

  def recache_stats!
    update!(
      product_count: commerce_products.where(status: "active").count,
      order_count: commerce_merchant.commerce_orders.where.not(status: %w[pending_payment cancelled]).count
    )
  end

  private
    def assign_storefront_id
      return if storefront_id.present?

      self.class.uncached do
        10.times do
          candidate = "stf_#{SecureRandom.alphanumeric(12).downcase}"
          unless self.class.exists?(storefront_id: candidate)
            self.storefront_id = candidate
            return
          end
        end
      end

      raise "Failed to generate unique storefront_id after 10 attempts"
    end

    def assign_slug
      self.slug = display_name.to_s.parameterize if slug.blank? && display_name.present?
    end

    def assign_store_url_slug
      return if store_url_slug.present?
      base = display_name.to_s.parameterize.presence || storefront_id.to_s
      candidate = base
      counter = 1
      while self.class.exists?(store_url_slug: candidate)
        candidate = "#{base}-#{counter}"
        counter += 1
      end
      self.store_url_slug = candidate
    end
end
