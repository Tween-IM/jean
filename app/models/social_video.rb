class SocialVideo < ApplicationRecord
  has_one_attached :source_video
  has_one_attached :generated_thumbnail

  has_many :social_views, dependent: :destroy
  has_many :social_likes, dependent: :destroy
  has_many :social_comments, dependent: :destroy
  has_many :views, class_name: "SocialView", dependent: :destroy
  has_many :likes, class_name: "SocialLike", dependent: :destroy
  has_many :comments, class_name: "SocialComment", dependent: :destroy

  before_validation :assign_video_id
  before_validation :assign_upload_id
  before_validation :publish_if_ready
  after_create :increment_creator_video_count

  validates :video_id, :creator_user_id, :upload_id, presence: true
  validates :video_id, uniqueness: true
  validates :visibility, inclusion: { in: %w[public followers unlisted private] }
  validates :status, inclusion: { in: %w[draft processing published deleted unavailable] }
  validates :moderation_status, inclusion: { in: %w[pending approved rejected limited] }

  scope :feedable, -> { where(status: "published", moderation_status: %w[approved limited]).where(visibility: %w[public unlisted]) }
  scope :latest, -> { order(published_at: :desc, created_at: :desc) }

  def liked_by?(user)
    social_likes.exists?(user_id: user.matrix_user_id)
  end

  def process_later
    SocialVideoProcessingJob.perform_later(self) if source_video.attached?
  end

  def visible_to?(user)
    return false if deleted? || moderation_status == "rejected"
    return true if creator_user_id == user.matrix_user_id
    return true if visibility.in?(%w[public unlisted]) && status == "published"
    return false unless visibility == "followers"

    SocialFollow.exists?(follower_user_id: user.matrix_user_id, creator_user_id: creator_user_id, status: "active")
  end

  def deleted?
    status == "deleted"
  end

  private
    def assign_video_id
      self.video_id ||= "vid_#{SecureRandom.alphanumeric(12).downcase}"
    end

    def assign_upload_id
      self.upload_id ||= "upl_#{SecureRandom.alphanumeric(12).downcase}"
    end

    def publish_if_ready
      return unless status.blank? || status == "processing"

      if playback_url.present?
        self.status = "published"
        self.moderation_status = "approved" if moderation_status.blank? || moderation_status == "pending"
        self.published_at ||= Time.current
      end
    end

    def increment_creator_video_count
      SocialCreatorProfile.find_by(user_id: creator_user_id)&.increment!(:video_count)
    end
end
