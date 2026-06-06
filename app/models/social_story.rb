# frozen_string_literal: true

class SocialStory < ApplicationRecord
  belongs_to :social_creator_profile, foreign_key: :creator_user_id, primary_key: :user_id, optional: true
  has_one_attached :source_media
  has_many :social_story_views, dependent: :destroy

  before_validation :assign_story_id, on: :create
  before_validation :set_expires_at, on: :create
  before_validation :set_default_status, on: :create

  validates :story_id, :creator_user_id, :media_type, presence: true
  validates :media_url, presence: true, unless: -> { source_media.attached? || media_type == "text" }
  validates :caption, presence: true, if: -> { media_type == "text" }
  validates :story_id, uniqueness: true
  validates :media_type, inclusion: { in: %w[image video text] }
  validates :status, inclusion: { in: %w[active deleted] }
  validates :duration_seconds, numericality: { less_than_or_equal_to: 60 }, allow_nil: true

  scope :active, -> { where(status: "active").where("expires_at > ?", Time.current) }
  scope :expired, -> { where("expires_at <= ?", Time.current) }
  scope :latest, -> { order(created_at: :desc) }

  def deleted?
    status == "deleted"
  end

  def expired?
    expires_at <= Time.current
  end

  def viewed_by?(user)
    social_story_views.exists?(viewer_user_id: user.matrix_user_id)
  end

  private

    def assign_story_id
      return if story_id.present?

      # Disable query cache so exists? checks are always fresh.
      # Rails caches SELECT results within a request; without this,
      # a collision on the first attempt returns a stale cached
      # result for the second attempt even with a different ID.
      self.class.uncached do
        10.times do
          candidate = "story_#{SecureRandom.alphanumeric(12).downcase}"
          unless self.class.exists?(story_id: candidate)
            self.story_id = candidate
            return
          end
        end
      end

      raise "Failed to generate unique story_id after 10 attempts"
    end

    def set_expires_at
      self.expires_at ||= 24.hours.from_now
    end

    def set_default_status
      self.status ||= "active"
    end
end
