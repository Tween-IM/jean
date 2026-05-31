# frozen_string_literal: true
class GiftOpening < ApplicationRecord
  self.table_name = :gift_openings
  self.primary_key = :id

  belongs_to :group_gift, class_name: "GroupGift", foreign_key: :group_gift_id

  validates :group_gift_id, presence: true
  validates :user_id, presence: true
  validates :amount, numericality: { greater_than_or_equal_to: 0 }

  scope :for_user, ->(user_id) { where(user_id: user_id) }
  scope :recent, -> { order(created_at: :desc) }
end