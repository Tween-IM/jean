class SocialReport < ApplicationRecord
  belongs_to :social_video

  validates :reporter_user_id, :reason, presence: true
  validates :reporter_user_id, uniqueness: { scope: :social_video_id }
  validates :reason, inclusion: { in: %w[spam abuse nudity violence scam intellectual_property other] }
  validates :status, inclusion: { in: %w[open reviewing resolved dismissed] }
end
