# frozen_string_literal: true

class Api::V1::Social::AnalyticsController < Api::V1::Social::BaseController
  def show
    require_scope("social:analytics")

    post = find_post
    return render_forbidden if post.creator_user_id != @current_user.matrix_user_id

    render json: { analytics: analytics_json(post) }
  end

  private

  def analytics_json(post)
    views_breakdown = post.social_views.group(:completed).count.transform_keys do |completed|
      completed ? "completed" : "partial"
    end

    {
      post_id: post.post_id,
      view_count: post.view_count,
      like_count: post.like_count,
      comment_count: post.comment_count,
      share_count: post.share_count,
      bookmark_count: post.social_bookmarks.count,
      unique_viewers: post.social_views.select(:viewer_user_id).distinct.count,
      views_breakdown: views_breakdown,
      avg_watch_time_ms: average_watch_time(post),
      top_commenters: top_commenters(post),
      created_at: post.created_at
    }
  end

  def average_watch_time(post)
    result = post.social_views.average(:watched_ms)
    result&.to_i || 0
  end

  def top_commenters(post, limit: 5)
    post.social_comments
      .active
      .group(:author_user_id)
      .count
      .sort_by { |_, count| -count }
      .first(limit)
      .map { |user_id, count| { user_id: user_id, comment_count: count } }
  end

  def render_forbidden
    render json: { error: "forbidden", message: "Analytics only available to the post creator" }, status: :forbidden
  end
end
