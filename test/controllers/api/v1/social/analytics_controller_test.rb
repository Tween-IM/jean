# frozen_string_literal: true

require "test_helper"

class Api::V1::Social::AnalyticsControllerTest < ActionDispatch::IntegrationTest
  test "creator can view their own video analytics" do
    creator = create_user("analytics_creator")
    video = SocialPost.create!(
      post_id: "vid_analytics_test",
      creator_user_id: creator.matrix_user_id,
      media_upload_id: "upl_analytics",
      status: "published",
      view_count: 10,
      like_count: 5,
      comment_count: 3,
      share_count: 2
    )
    SocialLike.create!(social_post: video, user_id: creator.matrix_user_id)
    SocialComment.create!(social_post: video, author_user_id: creator.matrix_user_id, body: "Great!")

    get api_v1_social_post_analytics_url(video.post_id),
      headers: tep_headers(creator, "social:analytics social:read"),
      as: :json

    assert_response :success
    analytics = response.parsed_body["analytics"]
    assert_equal video.post_id, analytics["post_id"]
    assert_equal 10, analytics["view_count"]
    assert_equal 6, analytics["like_count"]
    assert_equal 4, analytics["comment_count"]
    assert_equal 2, analytics["share_count"]
  end

  test "non-creator cannot view video analytics" do
    creator = create_user("analytics_owner")
    other = create_user("analytics_other")
    video = SocialPost.create!(
      post_id: "vid_noanalytics",
      creator_user_id: creator.matrix_user_id,
      media_upload_id: "upl_noana",
      status: "published",
      view_count: 10
    )

    get api_v1_social_post_analytics_url(video.post_id),
      headers: tep_headers(other, "social:analytics social:read"),
      as: :json

    assert_response :forbidden
  end

  test "creator sees view breakdown and top commenters" do
    creator = create_user("breakdown_creator")
    viewer1 = create_user("viewer1")
    viewer2 = create_user("viewer2")
    commenter1 = create_user("commenter1")
    commenter2 = create_user("commenter2")
    video = SocialPost.create!(
      post_id: "vid_breakdown",
      creator_user_id: creator.matrix_user_id,
      media_upload_id: "upl_break",
      status: "published"
    )
    SocialView.create!(social_post: video, viewer_user_id: viewer1.matrix_user_id, session_id: "sess_f", watched_ms: 10000, completed: true)
    SocialView.create!(social_post: video, viewer_user_id: viewer2.matrix_user_id, session_id: "sess_p", watched_ms: 3000, completed: false)
    SocialComment.create!(social_post: video, author_user_id: commenter1.matrix_user_id, body: "Nice!", status: "active")
    SocialComment.create!(social_post: video, author_user_id: commenter2.matrix_user_id, body: "Cool!", status: "active")

    get api_v1_social_post_analytics_url(video.post_id),
      headers: tep_headers(creator, "social:analytics"),
      as: :json

    assert_response :success
    analytics = response.parsed_body["analytics"]
    assert_equal 2, analytics["unique_viewers"]
    assert_equal 6500, analytics["avg_watch_time_ms"]
    assert_equal 2, analytics["top_commenters"].length
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
