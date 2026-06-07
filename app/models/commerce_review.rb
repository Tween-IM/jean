# frozen_string_literal: true
class CommerceReview < ApplicationRecord
  belongs_to :commerce_product, optional: true
  belongs_to :commerce_merchant
  belongs_to :commerce_order, optional: true

  before_validation :assign_review_id

  validates :review_id, :buyer_user_id, :rating, presence: true
  validates :review_id, uniqueness: true
  validates :rating, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 5 }
  validates :status, inclusion: { in: %w[pending approved rejected] }

  scope :approved, -> { where(status: "approved") }
  scope :for_product, ->(product_id) { where(commerce_product_id: product_id) }
  scope :for_merchant, ->(merchant_id) { where(commerce_merchant_id: merchant_id) }

  after_save :recache_product_stats, if: -> { saved_change_to_status? && status == "approved" }
  after_save :recache_merchant_stats, if: -> { saved_change_to_status? && status == "approved" }

  private
    def assign_review_id
      return if review_id.present?

      self.class.uncached do
        10.times do
          candidate = "rev_#{SecureRandom.alphanumeric(12).downcase}"
          unless self.class.exists?(review_id: candidate)
            self.review_id = candidate
            return
          end
        end
      end

      raise "Failed to generate unique review_id after 10 attempts"
    end

    def recache_product_stats
      commerce_product&.recache_stats!
    end

    def recache_merchant_stats
      # Update storefront ratings if needed
      commerce_merchant.commerce_storefronts.each(&:recache_stats!)
    end
end
