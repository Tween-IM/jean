class Api::V1::Social::LikesController < Api::V1::Social::BaseController
  def create
    require_scope("social:engage")

    video = find_video
    return if ensure_video_visible(video)

    like = video.social_likes.find_or_create_by!(user_id: @current_user.matrix_user_id)
    render json: { like_id: like.id, video: video_json(video.reload) }, status: :created
  end

  def destroy
    require_scope("social:engage")

    video = find_video
    like = video.social_likes.find_by(user_id: @current_user.matrix_user_id)
    like&.destroy!

    head :no_content
  end
end
