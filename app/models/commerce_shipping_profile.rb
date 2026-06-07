# frozen_string_literal: true
class CommerceShippingProfile < ApplicationRecord
  belongs_to :commerce_merchant
  has_many :commerce_product_shipping, dependent: :destroy
  has_many :commerce_products, through: :commerce_product_shipping

  before_validation :assign_shipping_profile_id

  validates :shipping_profile_id, :name, presence: true
  validates :shipping_profile_id, uniqueness: true
  validates :status, inclusion: { in: %w[active inactive] }

  scope :active, -> { where(status: "active") }

  def calculate_shipping(destination_country:, destination_state: nil, weight_grams: nil, subtotal_cents: 0)
    # Free shipping check
    if free_shipping_threshold_cents.present? && subtotal_cents >= free_shipping_threshold_cents
      return { rate_cents: 0, currency: "NGN", delivery_days: processing_time_days, name: name }
    end

    # Find matching zone
    zone = zones&.find do |z|
      z["countries"]&.include?(destination_country) ||
        (destination_state.present? && z["states"]&.include?(destination_state))
    end

    if zone.nil?
      return { rate_cents: nil, currency: "NGN", error: "No shipping available to this location" }
    end

    rate = zone["rate_cents"] || 0
    # Weight-based calculation if applicable
    if weight_grams.present? && zone["rate_per_gram_cents"].present?
      rate += (weight_grams * zone["rate_per_gram_cents"]).to_i
    end

    {
      rate_cents: rate,
      currency: zone["currency"] || "NGN",
      delivery_days: processing_time_days + (zone["transit_days"] || 0),
      name: name
    }
  end

  private
    def assign_shipping_profile_id
      return if shipping_profile_id.present?

      self.class.uncached do
        10.times do
          candidate = "sp_#{SecureRandom.alphanumeric(12).downcase}"
          unless self.class.exists?(shipping_profile_id: candidate)
            self.shipping_profile_id = candidate
            return
          end
        end
      end

      raise "Failed to generate unique shipping_profile_id after 10 attempts"
    end
end
