# frozen_string_literal: true

require "test_helper"

# Regression tests for the Flutter-mobile body shape.
#
# The deployed Flutter client (tween-app/lib/social/core/api_client.dart)
# sends flat top-level bodies (e.g. `{ signed_blob_id, content_type, caption }`)
# while the original controller contract expected wrapped bodies
# (e.g. `{ post: { ... } }`). The controllers now accept BOTH shapes via
# the SocialParams concern. These tests pin down the flat shape so that
# future changes can't silently regress the deployed mobile client.
class SocialFlatBodyTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = User.create!(
      matrix_user_id: "@flat-body:tween.im",
      matrix_username: "flat-body:tween.im",
      matrix_homeserver: "tween.im"
    )
    @creator = SocialCreatorProfile.create!(
      user_id: @user.matrix_user_id,
      handle: "flatbody",
      display_name: "Flat Body"
    )
    @token = TepTokenService.encode(
      { user_id: @user.matrix_user_id, miniapp_id: "ma_tweensocial" },
      scopes: %w[social:read social:write social:engage]
    )
    @headers = { "Authorization" => "Bearer #{@token}", "Content-Type" => "application/json" }
  end

  test "create post accepts flat body shape" do
    blob = ActiveStorage::Blob.create_before_direct_upload!(
      filename: "photo.jpg",
      byte_size: 1024,
      checksum: Base64.strict_encode64(Digest::MD5.digest("photo")),
      content_type: "image/jpeg"
    )
    blob.service.upload(blob.key, StringIO.new("photo"), checksum: blob.checksum)

    post "/api/v1/social/posts",
         params: {
           signed_blob_id: blob.signed_id,
           content_type: "photo",
           caption: "Hello from flat body",
           status: "published"
         }.to_json,
         headers: @headers

    assert_response :created
    body = response.parsed_body
    assert_equal "photo", body.dig("post", "content_type")
    assert_equal "Hello from flat body", body.dig("post", "caption")
    assert_equal "published", body.dig("post", "status")
  end

  test "create story accepts flat body shape" do
    blob = ActiveStorage::Blob.create_before_direct_upload!(
      filename: "story.mp4",
      byte_size: 2048,
      checksum: Base64.strict_encode64(Digest::MD5.digest("story")),
      content_type: "video/mp4"
    )
    blob.service.upload(blob.key, StringIO.new("story"), checksum: blob.checksum)

    post "/api/v1/social/stories",
         params: {
           signed_blob_id: blob.signed_id,
           media_type: "video",
           caption: "Story caption",
           duration_seconds: 12
         }.to_json,
         headers: @headers

    assert_response :created
    body = response.parsed_body
    assert_equal "video", body.dig("story", "media_type")
    assert_equal "Story caption", body.dig("story", "caption")
    assert_equal 12, body.dig("story", "duration")
  end

  test "create post is idempotent when Idempotency-Key header is replayed" do
    blob = ActiveStorage::Blob.create_before_direct_upload!(
      filename: "idem.jpg",
      byte_size: 512,
      checksum: Base64.strict_encode64(Digest::MD5.digest("idem")),
      content_type: "image/jpeg"
    )
    blob.service.upload(blob.key, StringIO.new("idem"), checksum: blob.checksum)

    idem_key = SecureRandom.uuid
    body = { signed_blob_id: blob.signed_id, content_type: "photo", caption: "idempotent" }.to_json
    headers = @headers.merge("Idempotency-Key" => idem_key)

    post "/api/v1/social/posts", params: body, headers: headers
    assert_response :created
    first_post_id = response.parsed_body.dig("post", "post_id")
    assert SocialPost.where(creator_user_id: @user.matrix_user_id, caption: "idempotent").count == 1

    post "/api/v1/social/posts", params: body, headers: headers
    assert_response :ok
    assert_equal first_post_id, response.parsed_body.dig("post", "post_id")
    assert_equal true, response.parsed_body["idempotent_replay"]
    assert SocialPost.where(creator_user_id: @user.matrix_user_id, caption: "idempotent").count == 1
  end

  test "following returns wrapped creators list" do
    target = SocialCreatorProfile.create!(
      user_id: "@followed:tween.im",
      handle: "followed",
      display_name: "Followed Creator"
    )
    SocialFollow.create!(
      follower_user_id: @user.matrix_user_id,
      creator_user_id: target.user_id,
      status: "active"
    )

    get "/api/v1/social/following", headers: @headers

    assert_response :success
    body = response.parsed_body
    assert body["creators"].is_a?(Array), "Expected wrapped {creators: []} response"
    assert body["creators"].any? { |c| c["user_id"] == target.user_id }
  end

  test "post and creator responses include updated_at" do
    blob = ActiveStorage::Blob.create_before_direct_upload!(
      filename: "ts.jpg",
      byte_size: 256,
      checksum: Base64.strict_encode64(Digest::MD5.digest("ts")),
      content_type: "image/jpeg"
    )
    blob.service.upload(blob.key, StringIO.new("ts"), checksum: blob.checksum)

    post "/api/v1/social/posts",
         params: { signed_blob_id: blob.signed_id, content_type: "photo", caption: "ts" }.to_json,
         headers: @headers
    assert_response :created
    assert response.parsed_body.dig("post", "updated_at").present?

    get "/api/v1/social/creators/@#{@user.matrix_username.split(':').first}:tween.im", headers: @headers
    assert_response :success
    assert response.parsed_body.dig("creator", "updated_at").present?
  end
end
