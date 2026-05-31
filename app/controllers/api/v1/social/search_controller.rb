class Api::V1::Social::SearchController < Api::V1::Social::BaseController
  def show
    require_scope("social:read")

    query = params[:q].to_s.strip
    return render json: { videos: [], creators: [] } if query.blank?

    videos = ::SocialVideo.feedable.where("caption ILIKE ?", "%#{::SocialVideo.sanitize_sql_like(query)}%").latest.limit(limit_param(default: 20, max: 50))
    creators = ::SocialCreatorProfile.where("handle ILIKE :query OR display_name ILIKE :query", query: "%#{::SocialCreatorProfile.sanitize_sql_like(query)}%").limit(20)

    render json: {
      videos: videos.map { |video| video_json(video) },
      creators: creators.map { |creator| creator_json(creator) }
    }
  end
end
