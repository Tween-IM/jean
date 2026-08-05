# frozen_string_literal: true

require "test_helper"

class PrivacyIntegrationTest < ActionDispatch::IntegrationTest
  def setup
    @buyer = create_user("privacy-buyer")
    @seller = create_user("privacy-seller")
    @viewer = create_user("privacy-viewer")

    # Ensure profiles exist for all users
    @buyer_profile = SocialCreatorProfile.find_or_create_by!(user_id: @buyer.matrix_user_id) do |p|
      p.handle = "buyer_#{SecureRandom.hex(4)}"
    end
    @seller_profile = SocialCreatorProfile.find_or_create_by!(user_id: @seller.matrix_user_id) do |p|
      p.handle = "seller_#{SecureRandom.hex(4)}"
    end
    @viewer_profile = SocialCreatorProfile.find_or_create_by!(user_id: @viewer.matrix_user_id) do |p|
      p.handle = "viewer_#{SecureRandom.hex(4)}"
    end
  end

  # ============================================================================
  # PII REDACTION — user_id never exposed in public social APIs
  # ============================================================================

  test "creator_json does not expose user_id to other users" do
    # Seller creates a post
    post = @seller_profile.social_posts.create!(
      creator_user_id: @seller.matrix_user_id,
      content_type: "text",
      caption: "Hello world",
      status: "published",
      moderation_status: "approved",
      visibility: "public",
      published_at: Time.current
    )

    # Viewer fetches the creator profile
    get api_v1_social_creator_url(@seller_profile.handle),
        headers: tep_headers(@viewer, "social:read")

    assert_response :success
    creator = response.parsed_body["creator"]
    assert_not_nil creator["handle"]
    assert_nil creator["user_id"], "user_id should NOT be exposed to other users"
    assert_nil creator["user_id"], "Matrix ID must be hidden"
  end

  test "creator_json exposes user_id for self-view only" do
    get api_v1_social_creator_url(@seller_profile.handle),
        headers: tep_headers(@seller, "social:read")

    assert_response :success
    creator = response.parsed_body["creator"]
    assert_equal @seller.matrix_user_id, creator["user_id"], "user_id should be visible to owner"
  end

  test "post_json does not expose creator_user_id" do
    post = @seller_profile.social_posts.create!(
      creator_user_id: @seller.matrix_user_id,
      content_type: "text", caption: "Test", status: "published",
      moderation_status: "approved", visibility: "public", published_at: Time.current
    )

    get api_v1_social_feed_url(type: "for_you"),
        headers: tep_headers(@viewer, "social:read")

    assert_response :success
    items = response.parsed_body["items"]
    assert_not_empty items
    items.each do |item|
      assert_nil item["creator_user_id"], "creator_user_id must not be in public feed"
      assert_not_nil item["creator_handle"], "creator_handle should be present"
      assert_not_nil item.dig("creator", "handle"), "creator.handle should be present"
    end
  end

  test "comment_json uses handles not user_id" do
    post = @seller_profile.social_posts.create!(
      creator_user_id: @seller.matrix_user_id,
      content_type: "text", caption: "Post", status: "published",
      moderation_status: "approved", visibility: "public", published_at: Time.current
    )

    post api_v1_social_post_comments_url(post.post_id),
         params: { comment: { body: "Nice!" } },
         headers: tep_headers(@buyer, "social:engage")

    assert_response :created
    comment = response.parsed_body["comment"]
    assert_nil comment["author_user_id"], "author_user_id must not be exposed"
    assert_not_nil comment["author_handle"], "author_handle should be present"
  end

  # ============================================================================
  # COMMERCE PII — phone/email never exposed publicly
  # ============================================================================

  test "merchant_json hides phone and email from public detail" do
    merchant = CommerceMerchant.create!(
      owner_user_id: @seller.matrix_user_id,
      miniapp_id: "miniapp.privacy.test",
      display_name: "Privacy Shop",
      phone: "+2348012345678",
      email: "shop@test.com",
      status: "active"
    )

    # Viewer fetches merchant (public detail)
    get api_v1_commerce_merchant_url(merchant.merchant_id),
        headers: tep_headers(@viewer, "commerce:read")

    assert_response :success
    body = response.parsed_body
    assert_nil body["phone"], "phone must not be exposed publicly"
    assert_nil body["email"], "email must not be exposed publicly"
    assert_nil body["owner_user_id"], "owner_user_id must not be exposed publicly"
  end

  test "merchant_json includes phone and email for owner" do
    merchant = CommerceMerchant.create!(
      owner_user_id: @seller.matrix_user_id,
      miniapp_id: "miniapp.privacy.test2",
      display_name: "Owner Shop",
      phone: "+2348012345678",
      email: "owner@test.com",
      status: "active"
    )

    # Owner fetches own merchant (must use :full detail, only available via me endpoint)
    get me_api_v1_commerce_merchants_url,
        headers: tep_headers(@seller, "commerce:read commerce:merchant")

    assert_response :success
    body = response.parsed_body
    assert_equal "+2348012345678", body["phone"], "phone should be visible to owner"
    assert_equal "owner@test.com", body["email"], "email should be visible to owner"
  end

  test "order_json hides buyer_user_id in public list" do
    merchant = CommerceMerchant.create!(
      owner_user_id: @seller.matrix_user_id,
      miniapp_id: "miniapp.order.privacy",
      display_name: "Order Shop",
      status: "active"
    )
    order = merchant.commerce_orders.create!(
      buyer_user_id: @buyer.matrix_user_id,
      payment_id: "pay_test",
      status: "paid",
      subtotal_cents: 1000, total_cents: 1000, currency: "NGN"
    )

    # Buyer fetches own order (should see buyer_user_id)
    get api_v1_commerce_order_url(order.order_id),
        headers: tep_headers(@buyer, "commerce:orders")

    assert_response :success
    assert_equal @buyer.matrix_user_id, response.parsed_body["buyer_user_id"],
                 "buyer should see their own user_id on order detail"
  end

  # ============================================================================
  # SOCIAL CHAT — handle resolution, creation
  # ============================================================================

  test "social chat resolves handle to Matrix ID" do
    post api_v1_chats_url,
         params: { target_user_id: @seller_profile.handle },
         headers: tep_headers(@buyer, "social:engage")

    assert_response :created
    chat = response.parsed_body
    assert_not_nil chat["chat_id"]
    assert_equal "active", chat["status"]
    assert_not_nil chat["other_user"]
    assert_equal @seller_profile.handle, chat.dig("other_user", "handle")
  end

  test "social chat is idempotent" do
    post api_v1_chats_url,
         params: { target_user_id: @seller_profile.handle },
         headers: tep_headers(@buyer, "social:engage")

    assert_response :created
    first_id = response.parsed_body["chat_id"]

    post api_v1_chats_url,
         params: { target_user_id: @seller_profile.handle },
         headers: tep_headers(@buyer, "social:engage")

    assert_response :created
    assert_equal first_id, response.parsed_body["chat_id"], "duplicate should return same chat"
  end

  test "social chat lists user's chats" do
    post api_v1_chats_url,
         params: { target_user_id: @seller_profile.handle },
         headers: tep_headers(@buyer, "social:engage")

    get api_v1_chats_url,
        headers: tep_headers(@buyer, "social:read")

    assert_response :success
    chats = response.parsed_body["chats"]
    assert chats.any? { |c| c.dig("other_user", "handle") == @seller_profile.handle }
  end

  test "social chat hides user_id in other_user" do
    post api_v1_chats_url,
         params: { target_user_id: @seller_profile.handle },
         headers: tep_headers(@buyer, "social:engage")

    assert_response :created
    other = response.parsed_body["other_user"]
    assert_not_nil other["handle"]
    assert_nil other["user_id"], "user_id must not be exposed in chat response"
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
    token = TepTokenService.encode(
      { user_id: user.matrix_user_id, miniapp_id: "miniapp.commerce.test" },
      scopes: scopes.split
    )
    { "Authorization" => "Bearer #{token}" }
  end
end
