class SocialComment < ApplicationRecord
  belongs_to :social_video
  belongs_to :parent_comment, class_name: "SocialComment", optional: true
  has_many :replies, class_name: "SocialComment", foreign_key: :parent_comment_id, dependent: :destroy

  after_create -> { social_video.increment!(:comment_count) }
  after_destroy -> { social_video.decrement!(:comment_count) if social_video.comment_count.positive? }

  validates :author_user_id, :body, presence: true
  validates :status, inclusion: { in: %w[active deleted hidden] }

  scope :active, -> { where(status: "active") }
  scope :chronologically, -> { order(created_at: :asc) }
end
