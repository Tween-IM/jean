# frozen_string_literal: true
class SocialCommentLike < ApplicationRecord
  belongs_to :social_comment

  validates :social_comment_id, :user_id, presence: true
  validates :user_id, uniqueness: { scope: :social_comment_id }
end
