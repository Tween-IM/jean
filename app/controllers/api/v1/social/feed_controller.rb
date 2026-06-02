# frozen_string_literal: true

require "base64"

class Api::V1::Social::FeedController < Api::V1::Social::BaseController
  FEED_TYPES = %w[for_you following creator saved reels].freeze
  RANKED_FEED_SIZE = 500

  def show
    require_scope("social:read")

    feed_type = params[:type].presence || "for_you"
    cursor = params[:cursor]
    limit = limit_param

    posts, next_cursor = case feed_type
    when "following"
      following_feed(cursor, limit)
    when "creator"
      creator_feed(params[:creator_id], cursor, limit)
    when "saved"
      saved_feed(cursor, limit)
    when "reels"
      reels_feed(cursor, limit)
    else
      for_you_feed(cursor, limit)
    end

    preload_creator_profiles(posts)
    preload_user_engagement(posts)
    render json: {
      items: posts.map { |post| post_json(post) },
      next_cursor: next_cursor,
      has_more: next_cursor.present?,
      feed_type: feed_type
    }
  end

  private

  def for_you_feed(cursor, limit)
    ranked_feed(cursor, limit)
  end

  def following_feed(cursor, limit)
    following_ids = SocialFollow.active.where(follower_user_id: @current_user.matrix_user_id).pluck(:creator_user_id)
    return [ [], nil ] if following_ids.empty?

    query = ::SocialPost.feedable.where(creator_user_id: following_ids)
    apply_cursor(query, cursor, limit)
  end

  def creator_feed(creator_id, cursor, limit)
    return [ [], nil ] if creator_id.blank?

    query = ::SocialPost.feedable.where(creator_user_id: creator_id)
    apply_cursor(query, cursor, limit)
  end

  def saved_feed(cursor, limit)
    saved_post_ids = SocialBookmark.where(user_id: @current_user.matrix_user_id).pluck(:social_post_id)
    return [ [], nil ] if saved_post_ids.empty?

    query = ::SocialPost.feedable.where(id: saved_post_ids)
    apply_cursor(query, cursor, limit)
  end

  def reels_feed(cursor, limit)
    query = ::SocialPost.feedable.where(content_type: "video")
    apply_cursor(query, cursor, limit)
  end

  def ranked_feed(cursor, limit)
    engagement_score = "(1 + (like_count * 3) + (comment_count * 5) + (share_count * 10) + (view_count * 0.5))"
    recency_hours = "GREATEST(EXTRACT(EPOCH FROM (NOW() - COALESCE(published_at, created_at))) / 3600, 0.01)"
    ranked_ids = ::SocialPost.feedable
      .order(Arel.sql("(#{engagement_score}) / #{recency_hours} DESC"))
      .limit(RANKED_FEED_SIZE)
      .pluck(:id)

    return [ [], nil ] if ranked_ids.empty?

    query = ::SocialPost.feedable.where(id: ranked_ids)
    apply_cursor(query, cursor, limit)
  end

  def encode_cursor(post)
    Base64.urlsafe_encode64({
      published_at: post.published_at&.iso8601,
      created_at: post.created_at.iso8601,
      id: post.id
    }.to_json)
  end

  def decode_cursor(cursor)
    JSON.parse(Base64.urlsafe_decode64(cursor))
  rescue StandardError
    nil
  end

  def apply_cursor(query, cursor, limit)
    base_query = query.order(published_at: :desc, created_at: :desc)

    decoded = cursor.present? ? decode_cursor(cursor) : nil
    scoped = if decoded
      base_query.where(
        "published_at < :published_at OR (published_at = :published_at AND created_at < :created_at) OR (published_at = :published_at AND created_at = :created_at AND id < :id)",
        published_at: decoded["published_at"],
        created_at: decoded["created_at"],
        id: decoded["id"]
      )
    else
      base_query
    end

    results = scoped.limit(limit + 1).to_a
    has_more = results.length > limit
    trimmed = has_more ? results.first(limit) : results
    next_cursor_val = has_more ? encode_cursor(trimmed.last) : nil

    [trimmed, next_cursor_val]
  end
end
