# frozen_string_literal: true
class CommerceCategory < ApplicationRecord
  has_many :subcategories, class_name: "CommerceCategory", foreign_key: "parent_id", dependent: :destroy
  belongs_to :parent_category, class_name: "CommerceCategory", optional: true, foreign_key: "parent_id"
  has_many :commerce_products, dependent: :nullify

  before_validation :assign_category_id

  validates :category_id, :name, :slug, presence: true
  validates :category_id, uniqueness: true
  validates :slug, uniqueness: true
  validates :status, inclusion: { in: %w[active inactive] }

  scope :active, -> { where(status: "active") }
  scope :top_level, -> { where(parent_id: nil) }

  def full_hierarchy
    ancestors = []
    current = self
    while current.parent_category
      current = current.parent_category
      ancestors.unshift(current)
    end
    ancestors + [self]
  end

  private
    def assign_category_id
      return if category_id.present?

      self.class.uncached do
        10.times do
          candidate = "cat_#{SecureRandom.alphanumeric(12).downcase}"
          unless self.class.exists?(category_id: candidate)
            self.category_id = candidate
            return
          end
        end
      end

      raise "Failed to generate unique category_id after 10 attempts"
    end
end
