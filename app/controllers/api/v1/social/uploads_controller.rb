class Api::V1::Social::UploadsController < Api::V1::Social::BaseController
  def create
    require_scope("social:write")

    upload_id = "upl_#{SecureRandom.urlsafe_base64(18)}"

    render json: {
      upload_id: upload_id,
      upload_url: "tmcp://social/uploads/#{upload_id}",
      max_duration_ms: 180_000,
      accepted_mime_types: [ "video/mp4", "video/quicktime", "video/webm" ],
      status: "pending_upload"
    }, status: :created
  end
end
