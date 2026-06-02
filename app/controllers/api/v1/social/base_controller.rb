# frozen_string_literal: true

class Api::V1::Social::BaseController < Api::BaseController
  include Api::TepAuthenticatable
  include Api::RateLimitable

  before_action :authenticate_tep_token

  rate_limit action: :create, limit: 10, window: 60, key: "social:write::user_id"
  rate_limit action: :like, limit: 30, window: 60, key: "social:like::user_id"
  rate_limit action: :follow, limit: 20, window: 60, key: "social:follow::user_id"
  rate_limit action: :comment, limit: 20, window: 60, key: "social:comment::user_id"

  private

  def current_creator_profile
    @current_creator_profile ||= SocialCreatorProfile.find_or_create_by!(user_id: @current_user.matrix_user_id) do |profile|
      profile.handle = @current_user.matrix_username.to_s.split(":").first
      profile.display_name = @current_user.matrix_username
    end
  end

  def find_post
    ::SocialPost.find_by!(post_id: params[:post_id] || params[:id])
  end

  def find_creator_profile
    ::SocialCreatorProfile.find_by!(user_id: params[:creator_id] || params[:id])
  end

  def ensure_post_visible(post)
    return false if post.visible_to?(@current_user)

    render json: { error: "not_found", message: "Post not found" }, status: :not_found
    true
  end

  def ensure_post_owner(post)
    return false if post.creator_user_id == @current_user.matrix_user_id

    render json: { error: "forbidden", message: "Only the creator can change this post" }, status: :forbidden
    true
  end

  def render_errors(record)
    render json: { error: "validation_failed", messages: record.errors.full_messages }, status: :unprocessable_entity
  end

  def preload_creator_profiles(posts)
    creator_ids = posts.map(&:creator_user_id).uniq
    @creator_profiles = SocialCreatorProfile.where(user_id: creator_ids).index_by(&:user_id)
    # Pre-resolve which creators currently have an active story so the
    # `creator_json` serializer can include `has_active_story` without
    # N+1 queries on list endpoints (feed, comments, bookmarks, etc.).
    @creators_with_active_story = SocialCreatorProfile.user_ids_with_active_story
  end

  def preload_user_engagement(posts)
    post_ids = posts.map(&:id)
    @liked_post_ids = SocialLike.where(social_post_id: post_ids, user_id: @current_user.matrix_user_id).pluck(:social_post_id).to_set
    @bookmarked_post_ids = SocialBookmark.where(social_post_id: post_ids, user_id: @current_user.matrix_user_id).pluck(:social_post_id).to_set
  end

  def post_json(post)
    creator = @creator_profiles&.[](post.creator_user_id) || SocialCreatorProfile.find_by(user_id: post.creator_user_id)
    {
      post_id: post.post_id,
      content_type: post.content_type,
      creator_user_id: post.creator_user_id,
      creator: creator ? creator_json(creator) : nil,
      caption: post.caption,
      playback_url: post.playback_url,
      thumbnail_url: post.thumbnail_url,
      source_media_attached: post.source_media.attached?,
      duration_seconds: post.duration_seconds,
      visibility: post.visibility,
      status: post.status,
      moderation_status: post.moderation_status,
      commerce_refs: post.commerce_refs,
      view_count: post.view_count,
      like_count: post.like_count,
      comment_count: post.comment_count,
      share_count: post.share_count,
      liked: @liked_post_ids&.include?(post.id) || post.liked_by?(@current_user),
      bookmarked: @bookmarked_post_ids&.include?(post.id) || post.bookmarked_by?(@current_user),
      published_at: post.published_at,
      created_at: post.created_at
    }
  end

  def creator_json(profile)
    # When bulk-preloaded, use the cached set; otherwise fall back to a
    # direct query. Avoids N+1 on the feed without breaking ad-hoc lookups
    # (e.g. /creators/:id).
    has_story = if defined?(@creators_with_active_story) && @creators_with_active_story
      @creators_with_active_story.include?(profile.user_id)
    else
      profile.has_active_story?
    end

    {
      user_id: profile.user_id,
      handle: profile.handle,
      display_name: profile.display_name,
      avatar_url: profile.avatar_url,
      bio: profile.bio,
      follower_count: profile.follower_count,
      following_count: profile.following_count,
      post_count: profile.post_count,
      verified: profile.verified,
      has_active_story: has_story
    }
  end

  def comment_json(comment)
    {
      comment_id: comment.id,
      post_id: comment.social_post.post_id,
      parent_comment_id: comment.parent_comment_id,
      author_user_id: comment.author_user_id,
      body: comment.body,
      status: comment.status,
      created_at: comment.created_at
    }
  end

  def bookmark_json(bookmark)
    {
      bookmark_id: bookmark.id,
      post: post_json(bookmark.social_post),
      created_at: bookmark.created_at
    }
  end

  def share_json(share)
    {
      share_id: share.id,
      post_id: share.social_post.post_id,
      target: share.target,
      room_id: share.room_id,
      metadata: share.metadata,
      created_at: share.created_at
    }
  end

  def report_json(report)
    {
      report_id: report.id,
      post_id: report.social_post.post_id,
      reason: report.reason,
      status: report.status,
      created_at: report.created_at
    }
  end

  def limit_param(default: 20, max: 50)
    [[ params.fetch(:limit, default).to_i, 1 ].max, max].min
  end
end
