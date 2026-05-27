class Api::V1::Social::FeedController < Api::V1::Social::BaseController
  def show
    require_scope("social:read")

    videos = ::SocialVideo.feedable.latest.limit(limit_param).select { |video| video.visible_to?(@current_user) }

    render json: {
      videos: videos.map { |video| video_json(video) },
      next_cursor: nil
    }
  end
end
