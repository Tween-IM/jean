class SocialView < ApplicationRecord
  belongs_to :social_video

  before_validation :assign_viewed_at
  after_create :increment_video_view_count

  validates :viewer_user_id, :session_id, :viewed_at, presence: true
  validates :session_id, uniqueness: { scope: [ :social_video_id, :viewer_user_id ] }

  private
    def increment_video_view_count
      social_video.increment!(:view_count)
    end

    def assign_viewed_at
      self.viewed_at ||= Time.current
    end
end
