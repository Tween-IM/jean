# frozen_string_literal: true
class SocialBookmark < ApplicationRecord
  belongs_to :social_post

  validates :user_id, presence: true
  validates :user_id, uniqueness: { scope: :social_post_id }
end
