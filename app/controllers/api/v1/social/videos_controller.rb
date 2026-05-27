class Api::V1::Social::VideosController < Api::V1::Social::BaseController
  def create
    require_scope("social:write")

    video = current_creator_profile.social_videos.new(video_params)
    video.creator_user_id = @current_user.matrix_user_id

    if video.save
      render json: { video: video_json(video) }, status: :created
    else
      render_errors(video)
    end
  end

  def show
    require_scope("social:read")

    video = find_video
    return if ensure_video_visible(video)

    render json: { video: video_json(video) }
  end

  def destroy
    require_scope("social:write")

    video = find_video
    return if ensure_video_owner(video)

    video.update!(status: "deleted", deleted_at: Time.current)
    head :no_content
  end

  private

  def video_params
    params.require(:video).permit(:upload_id, :caption, :playback_url, :thumbnail_url, :duration_seconds, :width, :height, :visibility, :status, variants: [], commerce_refs: [])
  end
end
