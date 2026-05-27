class SocialBookmark < ApplicationRecord
  belongs_to :social_video

  validates :user_id, presence: true
  validates :user_id, uniqueness: { scope: :social_video_id }
end
