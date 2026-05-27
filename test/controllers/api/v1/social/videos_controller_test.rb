require "test_helper"

class Api::V1::Social::VideosControllerTest < ActionDispatch::IntegrationTest
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
