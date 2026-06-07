# frozen_string_literal: true
class CommerceWarehouse < ApplicationRecord
  belongs_to :commerce_merchant

  before_validation :assign_warehouse_id

  validates :warehouse_id, :name, presence: true
  validates :warehouse_id, uniqueness: true
  validates :status, inclusion: { in: %w[active inactive] }

  scope :active, -> { where(status: "active") }

  def full_address
    [address_line1, address_line2, city, state, postal_code, country].compact.join(", ")
  end

  private
    def assign_warehouse_id
      return if warehouse_id.present?

      self.class.uncached do
        10.times do
          candidate = "wh_#{SecureRandom.alphanumeric(12).downcase}"
          unless self.class.exists?(warehouse_id: candidate)
            self.warehouse_id = candidate
            return
          end
        end
      end

      raise "Failed to generate unique warehouse_id after 10 attempts"
    end
end
