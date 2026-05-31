# frozen_string_literal: true
class SocialFollow < ApplicationRecord
  after_create :increment_counts
  after_destroy :decrement_counts

  validates :follower_user_id, :creator_user_id, presence: true
  validates :creator_user_id, uniqueness: { scope: :follower_user_id }
  validates :status, inclusion: { in: %w[active muted blocked] }
  validate :cannot_follow_self

  scope :active, -> { where(status: "active") }

  private
    def cannot_follow_self
      errors.add(:creator_user_id, "cannot follow self") if follower_user_id == creator_user_id
    end

    def increment_counts
      SocialCreatorProfile.find_by(user_id: creator_user_id)&.increment!(:follower_count)
      SocialCreatorProfile.find_by(user_id: follower_user_id)&.increment!(:following_count)
    end

    def decrement_counts
      SocialCreatorProfile.find_by(user_id: creator_user_id)&.decrement!(:follower_count)
      SocialCreatorProfile.find_by(user_id: follower_user_id)&.decrement!(:following_count)
    end
end
