require "test_helper"

class Api::V1::Social::BookmarksControllerTest < ActionDispatch::IntegrationTest
  test "user can bookmark and list a video" do
    user = create_user("bookmark-buyer")
    video = create_video(user)

    post api_v1_social_post_bookmark_url(video.post_id), headers: tep_headers(user, "social:read social:engage"), as: :json

    assert_response :created
    assert_equal video.post_id, response.parsed_body.dig("bookmark", "post", "post_id")

    get api_v1_social_bookmarks_url, headers: tep_headers(user, "social:read"), as: :json

    assert_response :success
    assert_equal [ video.post_id ], response.parsed_body.fetch("bookmarks").map { |bookmark| bookmark.dig("post", "post_id") }
  end

  private

  def create_user(username)
    User.create!(
      matrix_user_id: "@#{username}:example.com",
      matrix_username: "#{username}:example.com",
      matrix_homeserver: "example.com"
    )
  end

  def create_video(user)
    SocialCreatorProfile.create!(user_id: user.matrix_user_id, handle: user.matrix_username.split(":").first)
    SocialPost.create!(creator_user_id: user.matrix_user_id, media_upload_id: "upl_#{SecureRandom.hex(4)}", playback_url: "https://cdn.example.test/video.mp4", caption: "searchable drop")
  end

  def tep_headers(user, scopes)
    token = TepTokenService.encode({ user_id: user.matrix_user_id, miniapp_id: "miniapp.social.test" }, scopes: scopes.split)
    { "Authorization" => "Bearer #{token}" }
  end
end
