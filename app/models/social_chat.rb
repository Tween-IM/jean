# frozen_string_literal: true

class SocialChat < ApplicationRecord
  validates :user_a_id, :user_b_id, presence: true
  validates :status, inclusion: { in: %w[active blocked destroyed] }
  validates :user_a_id, uniqueness: { scope: :user_b_id }

  scope :for_user, ->(user_id) { where("user_a_id = ? OR user_b_id = ?", user_id, user_id) }
  scope :active, -> { where(status: 'active') }

  def other_user_id(user_id)
    user_a_id == user_id ? user_b_id : user_a_id
  end

  def blocked?
    status == 'blocked'
  end

  def blocked_by?(user_id)
    blocked? && blocked_by_user_id == user_id
  end
end
