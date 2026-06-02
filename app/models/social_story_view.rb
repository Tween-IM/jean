# frozen_string_literal: true

class SocialStoryView < ApplicationRecord
  belongs_to :social_story

  validates :viewer_user_id, presence: true
  validates :social_story_id, uniqueness: { scope: :viewer_user_id }
end
