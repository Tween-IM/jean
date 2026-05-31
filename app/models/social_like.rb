# frozen_string_literal: true
class SocialLike < ApplicationRecord
  belongs_to :social_post

  after_create -> { social_video.increment!(:like_count) }
  after_destroy -> { social_video.decrement!(:like_count) if social_video.like_count.positive? }

  validates :user_id, presence: true
  validates :user_id, uniqueness: { scope: :social_video_id }
end
