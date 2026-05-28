require "test_helper"

class Api::V1::Social::SearchControllerTest < ActionDispatch::IntegrationTest
  test "user can search videos and creators" do
    user = create_user("searcher")
    creator = create_user("canvas-maker")
    SocialCreatorProfile.create!(user_id: creator.matrix_user_id, handle: "canvas-maker", display_name: "Canvas Maker")
    SocialVideo.create!(creator_user_id: creator.matrix_user_id, upload_id: "upl_search", playback_url: "https://cdn.example.test/video.mp4", caption: "Canvas tote drop")

    get api_v1_social_search_url(q: "canvas"), headers: tep_headers(user, "social:read"), as: :json

    assert_response :success
    assert_equal [ "Canvas tote drop" ], response.parsed_body.fetch("videos").map { |video| video.fetch("caption") }
    assert_equal [ "canvas-maker" ], response.parsed_body.fetch("creators").map { |creator_json| creator_json.fetch("handle") }
  end

  private

  def create_user(username)
    User.create!(matrix_user_id: "@#{username}:example.com", matrix_username: "#{username}:example.com", matrix_homeserver: "example.com")
  end

  def tep_headers(user, scopes)
    token = TepTokenService.encode({ user_id: user.matrix_user_id, miniapp_id: "miniapp.social.test" }, scopes: scopes.split)
    { "Authorization" => "Bearer #{token}" }
  end
end
