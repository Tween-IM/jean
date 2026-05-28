class CommerceStorefront < ApplicationRecord
  belongs_to :commerce_merchant
  has_many :commerce_products, dependent: :nullify
  has_many :products, class_name: "CommerceProduct", dependent: :nullify

  before_validation :assign_storefront_id
  before_validation :assign_slug

  validates :storefront_id, :slug, :display_name, presence: true
  validates :storefront_id, uniqueness: true
  validates :slug, uniqueness: { scope: :commerce_merchant_id }
  validates :status, inclusion: { in: %w[draft published suspended] }

  private
    def assign_storefront_id
      self.storefront_id ||= "stf_#{SecureRandom.alphanumeric(12).downcase}"
    end

    def assign_slug
      self.slug = display_name.to_s.parameterize if slug.blank? && display_name.present?
    end
end
