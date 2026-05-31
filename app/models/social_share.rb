# frozen_string_literal: true
class SocialShare < ApplicationRecord
  belongs_to :social_post

  after_create -> { social_video.increment!(:share_count) }

  validates :user_id, :target, presence: true
  validates :target, inclusion: { in: %w[link matrix_room external dm] }
end
