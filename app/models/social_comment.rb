# frozen_string_literal: true
class SocialComment < ApplicationRecord
  belongs_to :social_post
  belongs_to :parent_comment, class_name: "SocialComment", optional: true
  has_many :replies, class_name: "SocialComment", foreign_key: :parent_comment_id, dependent: :destroy
  has_many :social_comment_likes, dependent: :destroy
  has_many :likes, class_name: "SocialCommentLike", dependent: :destroy

  after_create -> { social_post.increment!(:comment_count) }
  after_destroy -> { social_post.decrement!(:comment_count) if social_post.comment_count.positive? }

  validates :author_user_id, :body, presence: true
  validates :status, inclusion: { in: %w[active deleted hidden] }

  scope :active, -> { where(status: "active") }
  scope :chronologically, -> { order(created_at: :asc) }
end
