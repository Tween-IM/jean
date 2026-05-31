# frozen_string_literal: true
class SocialLike < ApplicationRecord
  belongs_to :social_post

  after_create -> { social_post.increment!(:like_count) }
  after_destroy -> { social_post.decrement!(:like_count) if social_post.like_count.positive? }

  validates :user_id, presence: true
  validates :user_id, uniqueness: { scope: :social_post_id }
end
