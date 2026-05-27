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
end
