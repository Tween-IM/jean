# frozen_string_literal: true

class SocialCreatorProfile < ApplicationRecord
  has_many :social_posts, primary_key: :user_id, foreign_key: :creator_user_id
  has_many :posts, class_name: "SocialPost", primary_key: :user_id, foreign_key: :creator_user_id
  has_many :social_stories, primary_key: :user_id, foreign_key: :creator_user_id
  has_many :followers, class_name: "SocialFollow", primary_key: :user_id, foreign_key: :creator_user_id
  has_many :following, class_name: "SocialFollow", primary_key: :user_id, foreign_key: :follower_user_id

  before_validation :normalize_handle

  validates :user_id, :handle, presence: true
  validates :user_id, :handle, uniqueness: true

  # Set of user_ids with at least one *unexpired, undeleted* story.
  # Used by the social JSON serializer to flag creators for the story ring.
  def self.user_ids_with_active_story
    SocialStory.active.distinct.pluck(:creator_user_id).to_set
  end

  def has_active_story?
    @has_active_story ||= SocialStory.active.exists?(creator_user_id: user_id)
  end

  private

  def normalize_handle
    self.handle = handle.to_s.downcase.delete_prefix("@") if handle.present?
  end
end
