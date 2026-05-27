class Api::V1::Social::VideosController < Api::V1::Social::BaseController
  def create
    require_scope("social:write")

    attributes = video_params
    signed_blob_id = attributes.delete(:signed_blob_id)
    attributes[:upload_id] ||= signed_blob_id if signed_blob_id.present?

    video = current_creator_profile.social_videos.new(attributes)
    video.creator_user_id = @current_user.matrix_user_id

    if video.save
      attach_source_video(video, signed_blob_id)
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
    params.require(:video).permit(:upload_id, :signed_blob_id, :caption, :playback_url, :thumbnail_url, :duration_seconds, :width, :height, :visibility, :status, variants: [], commerce_refs: [])
  end

  def attach_source_video(video, signed_blob_id)
    return if signed_blob_id.blank?

    video.source_video.attach(signed_blob_id)
    video.update!(status: "processing")
    video.process_later
  end
end
