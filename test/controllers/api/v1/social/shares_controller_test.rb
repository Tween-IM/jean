require "test_helper"

class Api::V1::Social::SharesControllerTest < ActionDispatch::IntegrationTest
  test "user can share a video" do
    user = create_user("share-buyer")
    video = create_video(user)

    post api_v1_social_post_shares_url(video.post_id),
      params: { share: { target: "matrix_room", room_id: "!room:example.com" } },
      headers: tep_headers(user, "social:engage"),
      as: :json

    assert_response :created
    assert_equal "matrix_room", response.parsed_body.dig("share", "target")
    assert_equal 1, response.parsed_body.dig("post", "share_count")
  end

  private

  def create_user(username)
    User.create!(matrix_user_id: "@#{username}:example.com", matrix_username: "#{username}:example.com", matrix_homeserver: "example.com")
  end

  def create_video(user)
    SocialCreatorProfile.create!(user_id: user.matrix_user_id, handle: user.matrix_username.split(":").first)
    SocialPost.create!(creator_user_id: user.matrix_user_id, media_upload_id: "upl_#{SecureRandom.hex(4)}", playback_url: "https://cdn.example.test/video.mp4")
  end

  def tep_headers(user, scopes)
    token = TepTokenService.encode({ user_id: user.matrix_user_id, miniapp_id: "miniapp.social.test" }, scopes: scopes.split)
    { "Authorization" => "Bearer #{token}" }
  end
end
