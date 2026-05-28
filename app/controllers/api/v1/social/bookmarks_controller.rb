class Api::V1::Social::BookmarksController < Api::V1::Social::BaseController
  def index
    require_scope("social:read")

    bookmarks = ::SocialBookmark.includes(:social_video).where(user_id: @current_user.matrix_user_id).order(created_at: :desc).limit(limit_param)
    render json: { bookmarks: bookmarks.map { |bookmark| bookmark_json(bookmark) } }
  end

  def create
    require_scope("social:engage")

    video = find_video
    return if ensure_video_visible(video)

    bookmark = video.social_bookmarks.find_or_create_by!(user_id: @current_user.matrix_user_id)
    render json: { bookmark: bookmark_json(bookmark), video: video_json(video) }, status: :created
  end

  def destroy
    require_scope("social:engage")

    video = find_video
    video.social_bookmarks.find_by(user_id: @current_user.matrix_user_id)&.destroy!
    head :no_content
  end
end
