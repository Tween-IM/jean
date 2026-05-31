# frozen_string_literal: true

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
      emit_video_published(video) if video.status == "published"
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
    emit_video_deleted(video)
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

  def emit_video_published(video)
    MatrixEventService.publish_video_published(
      video_id: video.video_id,
      creator_id: video.creator_user_id,
      caption: video.caption,
      thumbnail_url: video.thumbnail_url,
      published_at: video.published_at&.iso8601
    )
  end

  def emit_video_deleted(video)
    MatrixEventService.publish_video_deleted(
      video_id: video.video_id,
      creator_id: video.creator_user_id,
      deleted_at: video.deleted_at&.iso8601
    )
  end
end
