# frozen_string_literal: true

class Api::V1::Social::AnalyticsController < Api::V1::Social::BaseController
  def show
    require_scope("social:analytics")

    video = find_video
    return render_forbidden if video.creator_user_id != @current_user.matrix_user_id

    render json: { analytics: analytics_json(video) }
  end

  private

  def analytics_json(video)
    views_breakdown = video.social_views.group(:completed).count.transform_keys do |completed|
      completed ? "completed" : "partial"
    end

    {
      video_id: video.video_id,
      view_count: video.view_count,
      like_count: video.like_count,
      comment_count: video.comment_count,
      share_count: video.share_count,
      bookmark_count: video.social_bookmarks.count,
      unique_viewers: video.social_views.select(:viewer_user_id).distinct.count,
      views_breakdown: views_breakdown,
      avg_watch_time_ms: average_watch_time(video),
      top_commenters: top_commenters(video),
      created_at: video.created_at
    }
  end

  def average_watch_time(video)
    result = video.social_views.average(:watched_ms)
    result&.to_i || 0
  end

  def top_commenters(video, limit: 5)
    video.social_comments
      .active
      .group(:author_user_id)
      .count
      .sort_by { |_, count| -count }
      .first(limit)
      .map { |user_id, count| { user_id: user_id, comment_count: count } }
  end

  def render_forbidden
    render json: { error: "forbidden", message: "Analytics only available to video creator" }, status: :forbidden
  end
end
