# frozen_string_literal: true
class CommerceMerchant < ApplicationRecord
  has_many :commerce_storefronts, dependent: :destroy
  has_many :commerce_products, dependent: :destroy
  has_many :commerce_carts, dependent: :destroy
  has_many :commerce_orders, dependent: :restrict_with_error
  has_many :storefronts, class_name: "CommerceStorefront", dependent: :destroy
  has_many :products, class_name: "CommerceProduct", dependent: :destroy
  has_many :carts, class_name: "CommerceCart", dependent: :destroy
  has_many :orders, class_name: "CommerceOrder", dependent: :restrict_with_error

  before_validation :assign_merchant_id
  before_validation :assign_wallet_id

  validates :merchant_id, :miniapp_id, :display_name, :wallet_id, presence: true
  validates :merchant_id, uniqueness: true
  validates :status, inclusion: { in: %w[pending_review active suspended closed] }

  scope :active, -> { where(status: "active") }

  private
    def assign_merchant_id
      return if merchant_id.present?

      self.class.uncached do
        10.times do
          candidate = "mch_#{SecureRandom.alphanumeric(12).downcase}"
          unless self.class.exists?(merchant_id: candidate)
            self.merchant_id = candidate
            return
          end
        end
      end

      raise "Failed to generate unique merchant_id after 10 attempts"
    end

    def assign_wallet_id
      return if wallet_id.present?

      self.class.uncached do
        10.times do
          candidate = "tw_merchant_#{SecureRandom.alphanumeric(8).downcase}"
          unless self.class.exists?(wallet_id: candidate)
            self.wallet_id = candidate
            return
          end
        end
      end

      raise "Failed to generate unique wallet_id after 10 attempts"
    end
end
