class Api::V1::Social::ViewsController < Api::V1::Social::BaseController
  def create
    require_scope("social:engage")

    video = find_video
    return if ensure_video_visible(video)

    view = video.social_views.find_or_initialize_by(
      viewer_user_id: @current_user.matrix_user_id,
      session_id: params[:session_id].presence || SecureRandom.uuid
    )
    view.assign_attributes(view_params)
    view.viewer_user_id = @current_user.matrix_user_id

    if view.save
      render json: { view_id: view.id, video: video_json(video.reload) }, status: :created
    else
      render_errors(view)
    end
  end

  private

  def view_params
    params.permit(:watched_ms, :completed)
  end
end
