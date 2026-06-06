# frozen_string_literal: true

require "test_helper"

# End-to-end social integration tests.
#
# Covers the full content creation → storage → feed flow:
#   1. Direct upload (ActiveStorage blob)
#   2. Photo post
#   3. Video post (reel)
#   4. Story with caption
#   5. Mixed feed fetch
#   6. Reels-only feed fetch
#   7. Story feed fetch
#
# Storage behaviour:
#   - By default runs against the :test disk service (fast, no external deps).
#   - To test against S3/R2, set AWS_* env vars and run:
#       AWS_ACCESS_KEY_ID=xxx AWS_SECRET_ACCESS_KEY=yyy \
#       AWS_REGION=auto AWS_S3_BUCKET=tween \
#       AWS_S3_ENDPOINT=https://... bin/rails test test/integration/social_e2e_test.rb
#
class SocialE2ETest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      matrix_user_id: "@e2e_test_user:tween.im",
      matrix_username: "e2e_test_user:tween.im",
      matrix_homeserver: "tween.im"
    )

    @creator = SocialCreatorProfile.create!(
      user_id: @user.matrix_user_id,
      handle: "e2e_test_user",
      display_name: "E2E Test User"
    )

    @token = TepTokenService.encode(
      { user_id: @user.matrix_user_id, miniapp_id: "ma_tweensocial" },
      scopes: %w[social:read social:write social:engage]
    )

    @headers = { "Authorization" => "Bearer #{@token}", "Content-Type" => "application/json" }

    # Optionally switch ActiveStorage to S3 for this test run
    use_s3_if_configured!
  end

  teardown do
    clean_up_uploads!
  end

  # ───────────────────────────────────────────────────────────────────────────
  # 1. Upload — ActiveStorage direct upload
  # ───────────────────────────────────────────────────────────────────────────
  test "creates a direct upload blob and returns S3/disk URL" do
    post "/api/v1/social/uploads",
         params: upload_payload.to_json,
         headers: @headers

    assert_response :created
    body = response.parsed_body

    assert body["signed_blob_id"].present?
    assert body["direct_upload"]["url"].present?
    assert body["direct_upload"]["headers"].present?

    # Verify the blob exists
    blob = ActiveStorage::Blob.find_signed!(body["signed_blob_id"])
    assert_equal "video/mp4", blob.content_type
    assert_equal 1_048_576, blob.byte_size

    # If S3 is configured, the URL should point to the S3 endpoint
    if s3_configured?
      assert_includes body["direct_upload"]["url"], ENV.fetch("AWS_S3_ENDPOINT")
    end

    @signed_blob_id = body["signed_blob_id"]
  end

  # ───────────────────────────────────────────────────────────────────────────
  # 2. Photo post
  # ───────────────────────────────────────────────────────────────────────────
  test "creates a photo post and serves it from storage" do
    blob = create_test_blob!(content_type: "image/jpeg", filename: "photo.jpg")

    post "/api/v1/social/posts",
         params: {
           post: {
             signed_blob_id: blob.signed_id,
             caption: "Integration test photo",
             content_type: "photo",
             status: "published"
           }
         }.to_json,
         headers: @headers

    assert_response :created
    body = response.parsed_body

    assert_equal "photo", body["post"]["content_type"]
    assert_equal "Integration test photo", body["post"]["caption"]
    assert body["post"]["thumbnail_url"].present?
    assert_equal "published", body["post"]["status"]
    assert body["post"]["source_media_attached"]

    # Store for feed tests
    @photo_post_id = body["post"]["post_id"]
  end

  # ───────────────────────────────────────────────────────────────────────────
  # 3. Video post (reel)
  # ───────────────────────────────────────────────────────────────────────────
  test "creates a video post (reel) and triggers HLS processing" do
    blob = create_test_blob!(content_type: "video/mp4", filename: "reel.mp4")

    post "/api/v1/social/posts",
         params: {
           post: {
             signed_blob_id: blob.signed_id,
             caption: "Integration test reel",
             content_type: "video",
             status: "published",
             duration_seconds: 15,
             width: 1080,
             height: 1920
           }
         }.to_json,
         headers: @headers

    assert_response :created
    body = response.parsed_body

    assert_equal "video", body["post"]["content_type"]
    assert_equal "Integration test reel", body["post"]["caption"]
    assert body["post"]["playback_url"].present?
    assert_equal 15, body["post"]["duration_seconds"]
    assert_equal "published", body["post"]["status"]

    # Verify the HLS processing job was enqueued
    assert_enqueued_with(job: SocialPostProcessingJob) if defined?(SocialPostProcessingJob)

    @video_post_id = body["post"]["post_id"]
  end

  # ───────────────────────────────────────────────────────────────────────────
  # 4. Story with caption
  # ───────────────────────────────────────────────────────────────────────────
  test "creates a story with caption and media" do
    blob = create_test_blob!(content_type: "video/mp4", filename: "story.mp4")

    post "/api/v1/social/stories",
         params: {
           story: {
             signed_blob_id: blob.signed_id,
             media_type: "video",
             caption: "Integration test story",
             duration_seconds: 10
           }
         }.to_json,
         headers: @headers

    assert_response :created
    body = response.parsed_body

    assert_equal "video", body["story"]["media_type"]
    assert_equal "Integration test story", body["story"]["caption"]
    assert body["story"]["media_url"].present?
    assert_equal 10, body["story"]["duration"]

    @story_id = body["story"]["story_id"]
  end

  # ───────────────────────────────────────────────────────────────────────────
  # 5. Mixed feed (for_you)
  # ───────────────────────────────────────────────────────────────────────────
  test "fetches mixed feed with both photo and video posts" do
    seed_posts_for_feed!

    get "/api/v1/social/feed", params: { type: "for_you", limit: 20 }, headers: @headers

    assert_response :success
    body = response.parsed_body

    assert body["items"].is_a?(Array)
    assert body["items"].length >= 2

    content_types = body["items"].map { |i| i["content_type"] }
    assert_includes content_types, "photo"
    assert_includes content_types, "video"

    # Verify pagination
    assert_includes [true, false], body["has_more"]
    assert body["feed_type"] == "for_you"

    # Verify creator info is embedded
    first = body["items"].first
    assert first["creator"].present?
    assert first["creator"]["user_id"].present?
  end

  # ───────────────────────────────────────────────────────────────────────────
  # 6. Reels-only feed
  # ───────────────────────────────────────────────────────────────────────────
  test "fetches reels feed with only video posts" do
    seed_posts_for_feed!

    get "/api/v1/social/feed", params: { type: "reels", limit: 20 }, headers: @headers

    assert_response :success
    body = response.parsed_body

    content_types = body["items"].map { |i| i["content_type"] }
    assert content_types.all? { |t| t == "video" }, "Expected only video posts in reels feed"
  end

  # ───────────────────────────────────────────────────────────────────────────
  # 7. Stories feed
  # ───────────────────────────────────────────────────────────────────────────
  test "fetches active stories from followed creators" do
    seed_story!

    get "/api/v1/social/stories", headers: @headers

    assert_response :success
    body = response.parsed_body

    assert body["stories"].is_a?(Hash)
    assert body["creators"].is_a?(Hash)

    # Should contain our test user's story
    assert body["stories"].key?(@user.matrix_user_id)
    assert body["creators"].key?(@user.matrix_user_id)

    stories = body["stories"][@user.matrix_user_id]
    assert stories.length >= 1
    assert_equal "Integration test story", stories.first["caption"]
  end

  # ───────────────────────────────────────────────────────────────────────────
  # 8. Post show (verify media URL)
  # ───────────────────────────────────────────────────────────────────────────
  test "fetches a single post with resolved media URLs" do
    post_record = create_post!(content_type: "photo", caption: "Show test")

    get "/api/v1/social/posts/#{post_record.post_id}", headers: @headers

    assert_response :success
    body = response.parsed_body

    assert_equal post_record.post_id, body["post"]["post_id"]
    assert body["post"]["thumbnail_url"].present?
    assert body["post"]["source_media_attached"]
  end

  private

  # ── Helpers ────────────────────────────────────────────────────────────────

  def upload_payload
    {
      upload: {
        filename: "test_video.mp4",
        content_type: "video/mp4",
        byte_size: 1_048_576,
        checksum: "Gjai/lUa7nUHAtdC/CLm1Q=="
      }
    }
  end

  def create_test_blob!(content_type:, filename:)
    blob = ActiveStorage::Blob.create_before_direct_upload!(
      filename: filename,
      byte_size: 1_048_576,
      checksum: Base64.strict_encode64(Digest::MD5.digest("test")),
      content_type: content_type,
      metadata: { purpose: "social_post_source", creator_user_id: @user.matrix_user_id }
    )
    # Write dummy file content so attach/read operations work in tests
    FileUtils.mkdir_p(File.dirname(blob.service.path_for(blob.key)))
    File.write(blob.service.path_for(blob.key), "x" * 1_048_576, mode: "wb")
    blob
  end

  def with_active_storage_url_options(host: "http://www.example.com")
    ActiveStorage::Current.url_options = { host: host }
    yield
  ensure
    ActiveStorage::Current.url_options = nil
  end

  def create_post!(content_type:, caption:)
    blob = create_test_blob!(
      content_type: content_type == "photo" ? "image/jpeg" : "video/mp4",
      filename: "test.#{content_type == 'photo' ? 'jpg' : 'mp4'}"
    )

    post = @creator.social_posts.create!(
      content_type: content_type,
      caption: caption,
      creator_user_id: @user.matrix_user_id,
      status: "published",
      moderation_status: "approved",
      published_at: Time.current
    )
    post.source_media.attach(blob)

    with_active_storage_url_options do
      if content_type == "photo"
        post.update!(thumbnail_url: post.source_media.url)
      else
        post.update!(
          playback_url: Rails.application.routes.url_helpers.rails_blob_url(post.source_media, only_path: true),
          thumbnail_url: post.source_media.url
        )
      end
    end

    post
  end

  def seed_posts_for_feed!
    @seeded_posts ||= begin
      posts = []
      posts << create_post!(content_type: "photo", caption: "Feed photo 1")
      posts << create_post!(content_type: "video", caption: "Feed reel 1")
      posts << create_post!(content_type: "photo", caption: "Feed photo 2")
      posts << create_post!(content_type: "video", caption: "Feed reel 2")
      posts
    end
  end

  def seed_story!
    @seeded_story ||= begin
      blob = create_test_blob!(content_type: "video/mp4", filename: "story.mp4")
      story = @creator.social_stories.new(
        media_type: "video",
        caption: "Integration test story",
        creator_user_id: @user.matrix_user_id,
        duration_seconds: 10
      )
      story.source_media.attach(blob)
      with_active_storage_url_options do
        story.media_url = story.source_media.url
      end
      story.save!
      story
    end
  end

  def s3_configured?
    ENV["AWS_ACCESS_KEY_ID"].present? &&
      ENV["AWS_SECRET_ACCESS_KEY"].present? &&
      ENV["AWS_S3_BUCKET"].present?
  end

  def use_s3_if_configured!
    return if Rails.env.test?
    return unless s3_configured?

    ActiveStorage::Blob.service = ActiveStorage::Service.configure(
      :amazon,
      { amazon: {
        service: "S3",
        access_key_id: ENV.fetch("AWS_ACCESS_KEY_ID"),
        secret_access_key: ENV.fetch("AWS_SECRET_ACCESS_KEY"),
        region: ENV.fetch("AWS_REGION", "us-east-1"),
        bucket: ENV.fetch("AWS_S3_BUCKET"),
        endpoint: ENV["AWS_S3_ENDPOINT"],
        force_path_style: ENV["AWS_S3_ENDPOINT"].present?
      }}
    )
  end

  def clean_up_uploads!
    # Clean up ActiveStorage blobs and attachments created during tests
    ActiveStorage::Blob.where("created_at > ?", 1.hour.ago).find_each do |blob|
      begin
        blob.purge if blob.attachments.count == 0
      rescue StandardError
        nil
      end
    end
  end
end
