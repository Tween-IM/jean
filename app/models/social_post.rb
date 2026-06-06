# frozen_string_literal: true

class SocialPost < ApplicationRecord
  has_one_attached :source_media
  has_one_attached :generated_thumbnail

  has_many :social_views, dependent: :destroy
  has_many :social_likes, dependent: :destroy
  has_many :social_comments, dependent: :destroy
  has_many :social_bookmarks, dependent: :destroy
  has_many :social_shares, dependent: :destroy
  has_many :social_reports, dependent: :destroy
  has_many :views, class_name: "SocialView", dependent: :destroy
  has_many :likes, class_name: "SocialLike", dependent: :destroy
  has_many :comments, class_name: "SocialComment", dependent: :destroy

  before_validation :assign_post_id
  before_validation :assign_media_upload_id
  before_validation :publish_if_ready
  after_create :increment_creator_post_count

  validates :post_id, :creator_user_id, presence: true
  validates :post_id, uniqueness: true
  validates :visibility, inclusion: { in: %w[public followers unlisted private] }
  validates :status, inclusion: { in: %w[draft processing published deleted unavailable] }
  validates :moderation_status, inclusion: { in: %w[pending approved rejected limited] }
  validates :content_type, inclusion: { in: %w[photo video text] }

  scope :feedable, -> { where(status: "published", moderation_status: %w[approved limited]).where(visibility: %w[public unlisted]) }
  scope :latest, -> { order(published_at: :desc, created_at: :desc) }
  scope :photos, -> { where(content_type: "photo") }
  scope :videos, -> { where(content_type: "video") }

  def liked_by?(user)
    social_likes.exists?(user_id: user.matrix_user_id)
  end

  def bookmarked_by?(user)
    social_bookmarks.exists?(user_id: user.matrix_user_id)
  end

  def process_later
    return unless content_type == "video" && source_media.attached?

    SocialPostProcessingJob.perform_later(self)
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

    def assign_post_id
      return if post_id.present?

      loop do
        self.post_id = "post_#{SecureRandom.alphanumeric(12).downcase}"
        break unless self.class.exists?(post_id: post_id)
      end
    end

    def assign_media_upload_id
      return if media_upload_id.present?

      loop do
        self.media_upload_id = "upl_#{SecureRandom.alphanumeric(12).downcase}"
        break unless self.class.exists?(media_upload_id: media_upload_id)
      end
    end

    def publish_if_ready
      return unless status.blank? || status == "processing"

      if playback_url.present? || (content_type == "photo" && source_media.attached?) || content_type == "text"
        self.status = "published"
        self.moderation_status = "approved" if moderation_status.blank? || moderation_status == "pending"
        self.published_at ||= Time.current
      end
    end

    def increment_creator_post_count
      SocialCreatorProfile.find_by(user_id: creator_user_id)&.increment!(:post_count)
    end
end
