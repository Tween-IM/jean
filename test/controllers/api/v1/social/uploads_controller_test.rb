require "test_helper"

class Api::V1::Social::UploadsControllerTest < ActionDispatch::IntegrationTest
  test "creator can request a direct upload target" do
    user = User.create!(
      matrix_user_id: "@alice-upload:example.com",
      matrix_username: "alice-upload:example.com",
      matrix_homeserver: "example.com"
    )
    token = TepTokenService.encode({ user_id: user.matrix_user_id, miniapp_id: "miniapp.social.test" }, scopes: [ "social:write" ])

    post api_v1_social_uploads_url,
      params: {
        upload: {
          filename: "clip.mp4",
          byte_size: 1024,
          checksum: Base64.strict_encode64(Digest::MD5.digest("clip")),
          content_type: "video/mp4"
        }
      },
      headers: { "Authorization" => "Bearer #{token}" },
      as: :json

    assert_response :created
    assert response.parsed_body.fetch("signed_blob_id").present?
    assert response.parsed_body.dig("direct_upload", "url").present?
    assert_equal "pending_upload", response.parsed_body.fetch("status")
  end

  test "creator can request a direct upload target with flat body (deployed Flutter client)" do
    user = User.create!(
      matrix_user_id: "@alice-flat:example.com",
      matrix_username: "alice-flat:example.com",
      matrix_homeserver: "example.com"
    )
    token = TepTokenService.encode({ user_id: user.matrix_user_id, miniapp_id: "miniapp.social.test" }, scopes: [ "social:write" ])

    post api_v1_social_uploads_url,
      params: {
        filename: "image_8CE69234-84A5-4488-8B75-3F803175EAE7.jpeg",
        byte_size: 993_045,
        checksum: "hThmnxxKOy5ktUMCs7u0XQ==",
        content_type: "image/jpeg"
      },
      headers: { "Authorization" => "Bearer #{token}" },
      as: :json

    assert_response :created
    assert response.parsed_body.fetch("signed_blob_id").present?
    assert response.parsed_body.dig("direct_upload", "url").present?
  end

  test "rejects oversize image uploads at presign" do
    user = User.create!(
      matrix_user_id: "@alice-big:example.com",
      matrix_username: "alice-big:example.com",
      matrix_homeserver: "example.com"
    )
    token = TepTokenService.encode({ user_id: user.matrix_user_id, miniapp_id: "miniapp.social.test" }, scopes: [ "social:write" ])

    post api_v1_social_uploads_url,
      params: {
        upload: {
          filename: "huge.jpg",
          byte_size: 30 * 1024 * 1024,
          checksum: Base64.strict_encode64(Digest::MD5.digest("huge")),
          content_type: "image/jpeg"
        }
      },
      headers: { "Authorization" => "Bearer #{token}" },
      as: :json

    assert_response :unprocessable_entity
    assert_equal "file_too_large", response.parsed_body.dig("error")
    assert_equal Api::V1::Social::UploadsController::MAX_IMAGE_BYTES, response.parsed_body.dig("max_bytes")
  end

  test "rejects unsupported content types" do
    user = User.create!(
      matrix_user_id: "@alice-bad:example.com",
      matrix_username: "alice-bad:example.com",
      matrix_homeserver: "example.com"
    )
    token = TepTokenService.encode({ user_id: user.matrix_user_id, miniapp_id: "miniapp.social.test" }, scopes: [ "social:write" ])

    post api_v1_social_uploads_url,
      params: {
        upload: {
          filename: "doc.pdf",
          byte_size: 1024,
          checksum: Base64.strict_encode64(Digest::MD5.digest("doc")),
          content_type: "application/pdf"
        }
      },
      headers: { "Authorization" => "Bearer #{token}" },
      as: :json

    assert_response :unsupported_media_type
    assert_equal "unsupported_media_type", response.parsed_body.dig("error")
  end
end
