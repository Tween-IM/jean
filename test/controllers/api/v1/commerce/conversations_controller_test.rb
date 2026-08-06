require "test_helper"

class Api::V1::Commerce::ConversationsControllerTest < ActionDispatch::IntegrationTest
  def setup
    # Stub the bot's Matrix API for room creation / history reads.
    CommerceRelayService.define_singleton_method(:make_matrix_request) do |*args|
      if args.first == :get
        { "chunk" => [] }
      else
        { "room_id" => "!test_inquiry_room:#{ENV.fetch('MATRIX_DOMAIN', 'tween.im')}" }
      end
    end

    @seller = create_user("seller-conv")
    @buyer = create_user("buyer-conv")
    @other = create_user("other-conv")

    @merchant = CommerceMerchant.create!(
      owner_user_id: @seller.matrix_user_id,
      miniapp_id: "miniapp.conv.test",
      display_name: "Inquiry Shop",
      status: "active"
    )
    @product = @merchant.commerce_products.create!(
      title: "Used iPhone 12",
      status: "active",
      condition: "used",
      store_type: "marketplace"
    )
  end

  test "buyer can start a conversation with the seller" do
    post api_v1_commerce_product_contact_url(@product.product_id),
         headers: tep_headers(@buyer, "commerce:read"),
         as: :json

    assert_response :created
    body = response.parsed_body
    conversation = body["conversation"]
    assert_equal true, body["created"]
    assert_not_nil conversation["conversation_id"]
    assert_equal "buyer", conversation["role"]
    assert_equal "Inquiry Shop", conversation["seller_label"]
    assert_equal "Used iPhone 12", conversation.dig("product", "title")

    # Privacy: neither party's Matrix ID is ever in the response.
    refute_includes response.body, @buyer.matrix_user_id
    refute_includes response.body, @seller.matrix_user_id
  end

  test "second contact reuses the same conversation" do
    first = CommerceConversation.create!(
      buyer_user_id: @buyer.matrix_user_id,
      product_id: @product.product_id,
      matrix_room_id: "!existing:tween.im"
    )

    post api_v1_commerce_product_contact_url(@product.product_id),
         headers: tep_headers(@buyer, "commerce:read"),
         as: :json

    assert_response :created
    body = response.parsed_body
    assert_equal false, body["created"]
    assert_equal first.conversation_id, body.dig("conversation", "conversation_id")
  end

  test "seller can list and open the conversation" do
    conversation = CommerceConversation.create!(
      buyer_user_id: @buyer.matrix_user_id,
      product_id: @product.product_id,
      matrix_room_id: "!room:tween.im"
    )

    get api_v1_commerce_conversations_url,
        headers: tep_headers(@seller, "commerce:read"),
        as: :json

    assert_response :success
    conversations = response.parsed_body["conversations"]
    assert_equal 1, conversations.length
    assert_equal conversation.conversation_id, conversations.first["conversation_id"]
    assert_equal "seller", conversations.first["role"]
  end

  test "a stranger cannot access the conversation" do
    conversation = CommerceConversation.create!(
      buyer_user_id: @buyer.matrix_user_id,
      product_id: @product.product_id,
      matrix_room_id: "!room:tween.im"
    )

    get api_v1_commerce_conversation_url(conversation.conversation_id),
        headers: tep_headers(@other, "commerce:read"),
        as: :json

    assert_response :forbidden
  end

  test "buyer cannot contact their own listing" do
    post api_v1_commerce_product_contact_url(@product.product_id),
         headers: tep_headers(@seller, "commerce:read"),
         as: :json

    assert_response :unprocessable_entity
  end

  test "a participant can send and read messages through the relay" do
    conversation = CommerceConversation.create!(
      buyer_user_id: @buyer.matrix_user_id,
      product_id: @product.product_id,
      matrix_room_id: "!room:tween.im"
    )

    post messages_api_v1_commerce_conversation_url(conversation.conversation_id),
         params: { body: "Is this still available?" },
         headers: tep_headers(@buyer, "commerce:read"),
         as: :json

    assert_response :created
    message = response.parsed_body["message"]
    assert_equal "buyer", message["role"]
    assert_equal "Is this still available?", message["body"]

    get messages_api_v1_commerce_conversation_url(conversation.conversation_id),
        headers: tep_headers(@seller, "commerce:read"),
        as: :json

    assert_response :success
    assert_equal [], response.parsed_body["messages"]
  end

  test "a participant can send an image message" do
    conversation = CommerceConversation.create!(
      buyer_user_id: @buyer.matrix_user_id,
      product_id: @product.product_id,
      matrix_room_id: "!room:tween.im"
    )

    post messages_api_v1_commerce_conversation_url(conversation.conversation_id),
         params: {
           body: "Here it is",
           media_type: "image",
           media_url: "https://r2.tween.im/chat-photo.jpg",
           media_mime: "image/jpeg",
           media_size: 2048
         },
         headers: tep_headers(@buyer, "commerce:read"),
         as: :json

    assert_response :created
    message = response.parsed_body["message"]
    assert_equal "image", message["msgtype"]
    assert_equal "https://r2.tween.im/chat-photo.jpg", message["media_url"]
    assert_equal "image/jpeg", message["media_mime"]
  end

  test "history normalizes Matrix msgtypes for media messages" do
    conversation = CommerceConversation.create!(
      buyer_user_id: @buyer.matrix_user_id,
      product_id: @product.product_id,
      matrix_room_id: "!room:tween.im"
    )
    CommerceRelayService.define_singleton_method(:make_matrix_request) do |*args|
      if args.first == :get
        {
          "chunk" => [ {
            "type" => "m.room.message",
            "event_id" => "$audio1",
            "origin_server_ts" => 1_700_000_000_000,
            "content" => {
              "msgtype" => "m.audio",
              "body" => "Voice note.m4a",
              "url" => "https://r2.tween.im/vn.m4a",
              "m.tween.relay_role" => "buyer",
              "m.tween.relay_sender" => "Buyer",
              "info" => { "mimetype" => "audio/mp4", "size" => 1024 }
            }
          } ]
        }
      else
        { "room_id" => "!room:tween.im" }
      end
    end

    get messages_api_v1_commerce_conversation_url(conversation.conversation_id),
        headers: tep_headers(@seller, "commerce:read"),
        as: :json

    assert_response :success
    message = response.parsed_body["messages"].first
    assert_equal "audio", message["msgtype"]
    assert_equal "https://r2.tween.im/vn.m4a", message["media_url"]
    assert_equal "audio/mp4", message["media_mime"]
  end

  test "a new inquiry is unread for the seller and read once marked" do
    conversation = CommerceConversation.create!(
      buyer_user_id: @buyer.matrix_user_id,
      product_id: @product.product_id,
      matrix_room_id: "!room:tween.im",
      last_message_at: 1.minute.ago
    )

    get api_v1_commerce_conversation_url(conversation.conversation_id),
        headers: tep_headers(@seller, "commerce:read"),
        as: :json

    assert_response :success
    assert_equal true, response.parsed_body.dig("conversation", "unread")

    post read_api_v1_commerce_conversation_url(conversation.conversation_id),
         headers: tep_headers(@seller, "commerce:read"),
         as: :json

    assert_response :success
    assert_equal false, response.parsed_body.dig("conversation", "unread")
    assert conversation.reload.seller_last_read_at.present?
  end

  test "seller can close and reopen a conversation" do
    conversation = CommerceConversation.create!(
      buyer_user_id: @buyer.matrix_user_id,
      product_id: @product.product_id,
      matrix_room_id: "!room:tween.im"
    )

    patch api_v1_commerce_conversation_url(conversation.conversation_id),
          params: { status: "closed" },
          headers: tep_headers(@seller, "commerce:read"),
          as: :json

    assert_response :success
    assert_equal "closed", response.parsed_body.dig("conversation", "status")

    patch api_v1_commerce_conversation_url(conversation.conversation_id),
          params: { status: "open" },
          headers: tep_headers(@seller, "commerce:read"),
          as: :json

    assert_response :success
    assert_equal "open", response.parsed_body.dig("conversation", "status")
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
