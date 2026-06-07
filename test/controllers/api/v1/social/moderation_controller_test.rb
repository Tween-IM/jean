# frozen_string_literal: true

require "test_helper"

class Api::V1::Social::ModerationControllerTest < ActionDispatch::IntegrationTest
  test "moderator can approve a pending video" do
    owner = create_user("creator")
    moderator = create_user("mod")
    creator_profile = SocialCreatorProfile.create!(user_id: owner.matrix_user_id, handle: "creator1")
    video = SocialPost.create!(
      post_id: "vid_mod_test_1",
      creator_user_id: owner.matrix_user_id,
      media_upload_id: "upl_mod_1",
      caption: "Test video",
      status: "published",
      moderation_status: "pending"
    )

    post api_v1_social_moderation_post_status_url,
      params: { moderation: { moderation_status: "approved", post_ids: [video.post_id], reason: "Looks good" } },
      headers: tep_headers(moderator, "social:moderate social:read"),
      as: :json

    assert_response :success
    assert_equal "approved", response.parsed_body.dig("moderation_status")
    assert_equal moderator.matrix_user_id, response.parsed_body["moderated_by"]
  end

  test "moderator can reject a video" do
    owner = create_user("rejected_creator")
    moderator = create_user("mod2")
    video = SocialPost.create!(
      post_id: "vid_reject_test",
      creator_user_id: owner.matrix_user_id,
      media_upload_id: "upl_reject",
      caption: "Test reject",
      status: "published",
      moderation_status: "pending"
    )

    post api_v1_social_moderation_post_status_url,
      params: { moderation: { moderation_status: "rejected", post_ids: [video.post_id], reason: "Violates policy" } },
      headers: tep_headers(moderator, "social:moderate"),
      as: :json

    assert_response :success
    assert_equal "rejected", response.parsed_body.dig("moderation_status")
  end

  test "moderator can bulk update video status" do
    owner = create_user("bulk_creator")
    moderator = create_user("bulk_mod")
    video1 = SocialPost.create!(post_id: "vid_bulk_1", creator_user_id: owner.matrix_user_id, media_upload_id: "upl_b1", status: "published", moderation_status: "pending")
    video2 = SocialPost.create!(post_id: "vid_bulk_2", creator_user_id: owner.matrix_user_id, media_upload_id: "upl_b2", status: "published", moderation_status: "pending")

    post api_v1_social_moderation_bulk_update_url,
      params: { moderation: { moderation_status: "approved", post_ids: [video1.post_id, video2.post_id] } },
      headers: tep_headers(moderator, "social:moderate"),
      as: :json

    assert_response :success
    assert_equal 2, response.parsed_body["updated_count"]
    assert_equal "approved", response.parsed_body["moderation_status"]
  end

  test "moderator can list open reports" do
    reporter = create_user("reporter")
    owner = create_user("reported_creator")
    moderator = create_user("list_mod")
    video = SocialPost.create!(post_id: "vid_report_test", creator_user_id: owner.matrix_user_id, media_upload_id: "upl_rep", status: "published", moderation_status: "pending")
    SocialReport.create!(social_post: video, reporter_user_id: reporter.matrix_user_id, reason: "spam", status: "open")

    get api_v1_social_moderation_reports_url,
      params: { status: "open" },
      headers: tep_headers(moderator, "social:moderate")

    assert_response :success
    assert_equal "open", response.parsed_body["status"]
    assert_equal 1, response.parsed_body["reports"].length
  end

  test "moderator can resolve a report" do
    reporter = create_user("res_reporter")
    owner = create_user("res_owner")
    moderator = create_user("res_mod")
    video = SocialPost.create!(post_id: "vid_resolve", creator_user_id: owner.matrix_user_id, media_upload_id: "upl_res", status: "published", moderation_status: "pending")
    report = SocialReport.create!(social_post: video, reporter_user_id: reporter.matrix_user_id, reason: "spam", status: "open")

    post "http://www.example.com/api/v1/social/moderation/reports/#{report.id}/resolve",
      params: { moderation: { moderation_status: "rejected" } },
      headers: tep_headers(moderator, "social:moderate"),
      as: :json

    assert_response :success
    assert_equal "resolved", response.parsed_body.dig("report", "status")
  end

  test "regular user cannot access moderation endpoints" do
    user = create_user("regular_user")

    post api_v1_social_moderation_post_status_url,
      params: { moderation: { moderation_status: "approved" } },
      headers: tep_headers(user, "social:read social:write"),
      as: :json

    assert_response :forbidden
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
