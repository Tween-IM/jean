# frozen_string_literal: true

class Api::V1::Social::UploadsController < Api::V1::Social::BaseController
  ACCEPTED_MIME_TYPES = %w[
    video/mp4
    video/quicktime
    video/webm
    image/jpeg
    image/png
    image/heic
    image/webp
  ].freeze

  # Hard limits — anything larger is rejected at the presign step so the
  # client never uploads bytes the server cannot accept. These mirror the
  # client-side guards in tween-app/lib/social/core/upload_queue.dart.
  MAX_IMAGE_BYTES = 20 * 1024 * 1024
  MAX_VIDEO_BYTES = 100 * 1024 * 1024

  def create
    require_scope("social:write")

    filename     = upload_params.fetch(:filename)
    byte_size    = upload_params.fetch(:byte_size)
    checksum     = upload_params.fetch(:checksum)
    content_type = upload_params.fetch(:content_type)

    unless content_type.to_s.in?(ACCEPTED_MIME_TYPES)
      return render json: {
        error: "unsupported_media_type",
        message: "Unsupported content type '#{content_type}'",
        accepted_mime_types: ACCEPTED_MIME_TYPES
      }, status: :unsupported_media_type
    end

    max = content_type.to_s.start_with?("video/") ? MAX_VIDEO_BYTES : MAX_IMAGE_BYTES
    if byte_size.to_i <= 0
      return render json: { error: "invalid_byte_size", message: "byte_size must be positive" }, status: :unprocessable_entity
    end
    if byte_size.to_i > max
      return render json: {
        error: "file_too_large",
        message: "File exceeds the #{max} byte limit for this content type",
        max_bytes: max
      }, status: :unprocessable_entity
    end

    blob = ActiveStorage::Blob.create_before_direct_upload!(
      filename: filename,
      byte_size: byte_size,
      checksum: checksum,
      content_type: content_type,
      metadata: {
        purpose: "social_post_source",
        creator_user_id: @current_user.matrix_user_id,
        miniapp_id: @miniapp_id
      }
    )
    ActiveStorage::Current.url_options = { host: request.base_url }

    render json: {
      upload_id: blob.signed_id,
      signed_blob_id: blob.signed_id,
      direct_upload: {
        url: blob.service_url_for_direct_upload,
        headers: blob.service_headers_for_direct_upload
      },
      accepted_mime_types: ACCEPTED_MIME_TYPES,
      max_image_bytes: MAX_IMAGE_BYTES,
      max_video_bytes: MAX_VIDEO_BYTES,
      status: "pending_upload"
    }, status: :created
  rescue ActiveStorage::Blob::NotIdentifiedByServiceError => e
    render json: { error: "invalid_checksum", message: e.message }, status: :unprocessable_entity
  end

  private

  def upload_params
    # Accepts both `upload: { ... }` (Rails-conventional, used by tests) and
    # `{ filename, content_type, byte_size, checksum }` (what the deployed
    # Flutter client actually sends). See SocialParams concern.
    SocialParams.permit(
      params,
      wrapper: :upload,
      keys: %i[filename byte_size checksum content_type]
    )
  end
end
