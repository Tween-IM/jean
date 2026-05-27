require "test_helper"

class Api::V1::Social::VideosControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "creator can publish a short video and read it from the feed" do
    user = create_user("alice")
    headers = tep_headers(user, "social:read social:write")

    post api_v1_social_videos_url,
      params: {
        video: {
          upload_id: "upl_test_video",
          playback_url: "https://cdn.example.test/videos/one.mp4",
          thumbnail_url: "https://cdn.example.test/videos/one.jpg",
          duration_seconds: 14,
          caption: "Launch drop",
          commerce_refs: [ { product_id: "prod_test" } ]
        }
      },
      headers: headers,
      as: :json

    assert_response :created
    video_id = response.parsed_body.dig("video", "video_id")
    assert_equal "published", response.parsed_body.dig("video", "status")

    get api_v1_social_feed_url, headers: headers, as: :json

    assert_response :success
    assert_includes response.parsed_body.fetch("videos").map { |video| video.fetch("video_id") }, video_id
  end

  test "creator can create a video from a signed upload blob" do
    user = create_user("uploader")
    headers = tep_headers(user, "social:read social:write")
    blob = ActiveStorage::Blob.create_before_direct_upload!(
      filename: "clip.mp4",
      byte_size: 1024,
      checksum: Base64.strict_encode64(Digest::MD5.digest("clip")),
      content_type: "video/mp4"
    )
    blob.service.upload(blob.key, StringIO.new("clip"), checksum: blob.checksum)

    perform_enqueued_jobs only: SocialVideoProcessingJob do
      post api_v1_social_videos_url,
        params: {
          video: {
            signed_blob_id: blob.signed_id,
            caption: "Uploaded through TMCP"
          }
        },
        headers: headers,
        as: :json
    end

    assert_response :created
    video = SocialVideo.find_by!(video_id: response.parsed_body.dig("video", "video_id"))
    assert video.source_video.attached?
    assert_equal "published", video.status
    assert_match %r{/rails/active_storage/blobs/}, video.playback_url
  end

  private

  def create_user(username)
    User.create!(
      matrix_user_id: "@#{username}:example.com",
      matrix_username: "#{username}:example.com",
      matrix_homeserver: "example.com"
    )
  end

  def tep_headers(user, scopes)
    token = TepTokenService.encode({ user_id: user.matrix_user_id, miniapp_id: "miniapp.social.test" }, scopes: scopes.split)
    { "Authorization" => "Bearer #{token}" }
  end
end
