# frozen_string_literal: true
class CommercePromotion < ApplicationRecord
  belongs_to :commerce_merchant

  before_validation :assign_promotion_id

  validates :promotion_id, presence: true
  validates :promotion_id, uniqueness: true
  validates :status, inclusion: { in: %w[draft active paused completed cancelled] }
  validates :type, inclusion: { in: %w[featured_listing banner_ad search_boost] }, allow_blank: true

  scope :active, -> { where(status: "active").where("start_at <= ? AND end_at >= ?", Time.current, Time.current) }

  private
    def assign_promotion_id
      return if promotion_id.present?

      self.class.uncached do
        10.times do
          candidate = "promo_#{SecureRandom.alphanumeric(12).downcase}"
          unless self.class.exists?(promotion_id: candidate)
            self.promotion_id = candidate
            return
          end
        end
      end

      raise "Failed to generate unique promotion_id after 10 attempts"
    end
end
