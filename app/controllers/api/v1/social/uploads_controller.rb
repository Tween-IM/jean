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

  def create
    require_scope("social:write")

    blob = ActiveStorage::Blob.create_before_direct_upload!(
      filename: upload_params.fetch(:filename),
      byte_size: upload_params.fetch(:byte_size),
      checksum: upload_params.fetch(:checksum),
      content_type: upload_params.fetch(:content_type),
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
      status: "pending_upload"
    }, status: :created
  end

  private

  def upload_params
    permitted = params.require(:upload).permit(:filename, :byte_size, :checksum, :content_type)
    unless permitted[:content_type].to_s.in?(ACCEPTED_MIME_TYPES)
      raise ActionController::BadRequest, "Unsupported content type"
    end

    permitted
  end
end
