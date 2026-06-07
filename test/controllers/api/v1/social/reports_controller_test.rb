require "test_helper"

class Api::V1::Social::ReportsControllerTest < ActionDispatch::IntegrationTest
  test "user can report a video" do
    creator = create_user("reported-creator")
    reporter = create_user("reporter")
    video = create_video(creator)

    post api_v1_social_post_reports_url(video.post_id),
      params: { report: { reason: "spam", details: "Misleading listing" } },
      headers: tep_headers(reporter, "social:engage"),
      as: :json

    assert_response :created
    assert_equal "open", response.parsed_body.dig("report", "status")
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
