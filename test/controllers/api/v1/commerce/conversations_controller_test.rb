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

  test "history normalizes Matrix msgtypes for media messages" do    conversation = CommerceConversation.create!(
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

  test "seller offers a direct chat and the buyer accepts" do
    conversation = CommerceConversation.create!(
      buyer_user_id: @buyer.matrix_user_id,
      product_id: @product.product_id,
      matrix_room_id: "!room:tween.im"
    )

    post offer_dm_api_v1_commerce_conversation_url(conversation.conversation_id),
         headers: tep_headers(@seller, "commerce:read"),
         as: :json

    assert_response :success
    body = response.parsed_body["conversation"]
    assert_equal "dm_pending", body["status"]
    assert_equal "seller", body["dm_offered_by"]
    assert body["dm_room_id"].present?

    post accept_dm_api_v1_commerce_conversation_url(conversation.conversation_id),
         headers: tep_headers(@buyer, "commerce:read"),
         as: :json

    assert_response :success
    assert_equal "dm_active", response.parsed_body.dig("conversation", "status")
    conversation.reload
    assert_equal conversation.dm_room_id, response.parsed_body["dm_room_id"]
    assert conversation.reload.status == "dm_active"
  end

  test "declining a direct chat returns the conversation to open" do
    conversation = CommerceConversation.create!(
      buyer_user_id: @buyer.matrix_user_id,
      product_id: @product.product_id,
      matrix_room_id: "!room:tween.im",
      dm_room_id: "!dm_room:tween.im",
      dm_offered_by: "seller",
      status: "dm_pending"
    )

    post decline_dm_api_v1_commerce_conversation_url(conversation.conversation_id),
         headers: tep_headers(@buyer, "commerce:read"),
         as: :json

    assert_response :success
    body = response.parsed_body["conversation"]
    assert_equal "open", body["status"]
    assert_nil body["dm_offered_by"]
  end

  test "buyer can offer a direct chat" do
    conversation = CommerceConversation.create!(
      buyer_user_id: @buyer.matrix_user_id,
      product_id: @product.product_id,
      matrix_room_id: "!room:tween.im"
    )

    post offer_dm_api_v1_commerce_conversation_url(conversation.conversation_id),
         headers: tep_headers(@buyer, "commerce:read"),
         as: :json

    assert_response :success
    body = response.parsed_body["conversation"]
    assert_equal "dm_pending", body["status"]
    assert_equal "buyer", body["dm_offered_by"]
  end

  test "the offerer cannot accept their own direct chat" do
    conversation = CommerceConversation.create!(
      buyer_user_id: @buyer.matrix_user_id,
      product_id: @product.product_id,
      matrix_room_id: "!room:tween.im",
      dm_room_id: "!dm_room:tween.im",
      dm_offered_by: "buyer",
      status: "dm_pending"
    )

    post accept_dm_api_v1_commerce_conversation_url(conversation.conversation_id),
         headers: tep_headers(@buyer, "commerce:read"),
         as: :json

    assert_response :forbidden
    conversation.reload
    assert_equal "dm_pending", conversation.status
  end

  test "accepting a non-pending direct chat is rejected" do
    conversation = CommerceConversation.create!(
      buyer_user_id: @buyer.matrix_user_id,
      product_id: @product.product_id,
      matrix_room_id: "!room:tween.im",
      dm_room_id: "!dm_room:tween.im",
      dm_offered_by: "seller",
      status: "open"
    )

    post accept_dm_api_v1_commerce_conversation_url(conversation.conversation_id),
         headers: tep_headers(@buyer, "commerce:read"),
         as: :json

    assert_response :unprocessable_entity
  end

  test "DM rooms are deduped per buyer/seller pair" do
    second_product = @merchant.commerce_products.create!(
      title: "Another item",
      status: "active",
      condition: "used",
      store_type: "marketplace"
    )
    first = CommerceConversation.create!(
      buyer_user_id: @buyer.matrix_user_id,
      product_id: @product.product_id,
      matrix_room_id: "!room:tween.im"
    )
    second = CommerceConversation.create!(
      buyer_user_id: @buyer.matrix_user_id,
      product_id: second_product.product_id,
      matrix_room_id: "!room2:tween.im"
    )

    post offer_dm_api_v1_commerce_conversation_url(first.conversation_id),
         headers: tep_headers(@seller, "commerce:read"),
         as: :json
    assert_response :success
    first_room = response.parsed_body.dig("conversation", "dm_room_id")
    assert first_room.present?

    post offer_dm_api_v1_commerce_conversation_url(second.conversation_id),
         headers: tep_headers(@seller, "commerce:read"),
         as: :json
    assert_response :success
    second_room = response.parsed_body.dig("conversation", "dm_room_id")

    assert_equal first_room, second_room
    assert_equal 1, CommerceDmRoom.count
  end

  test "payment_recipient returns the counterparty id only to a participant" do
    conversation = CommerceConversation.create!(
      buyer_user_id: @buyer.matrix_user_id,
      product_id: @product.product_id,
      matrix_room_id: "!room:tween.im"
    )

    # Buyer → seller is the recipient.
    get payment_recipient_api_v1_commerce_conversation_url(conversation.conversation_id),
        headers: tep_headers(@buyer, "commerce:read"),
        as: :json
    assert_response :success
    body = response.parsed_body
    assert_equal @seller.matrix_user_id, body["recipient_user_id"]
    assert_equal "Inquiry Shop", body["recipient_label"]

    # Seller → buyer is the recipient.
    get payment_recipient_api_v1_commerce_conversation_url(conversation.conversation_id),
        headers: tep_headers(@seller, "commerce:read"),
        as: :json
    assert_response :success
    assert_equal @buyer.matrix_user_id, response.parsed_body["recipient_user_id"]

    # A stranger is not allowed.
    get payment_recipient_api_v1_commerce_conversation_url(conversation.conversation_id),
        headers: tep_headers(@other, "commerce:read"),
        as: :json
    assert_response :forbidden
  end

  test "payment_relay posts a payment event into the relay room" do
    conversation = CommerceConversation.create!(
      buyer_user_id: @buyer.matrix_user_id,
      product_id: @product.product_id,
      matrix_room_id: "!room:tween.im"
    )

    post payments_relay_api_v1_commerce_conversation_url(conversation.conversation_id),
         params: { transfer_id: "p2p_abc", amount: 50.0, currency: "NGN", status: "completed" },
         headers: tep_headers(@buyer, "commerce:read"),
         as: :json

    assert_response :success
    assert_equal "relayed", response.parsed_body["status"]

    # Strangers cannot relay a payment into the room.
    post payments_relay_api_v1_commerce_conversation_url(conversation.conversation_id),
         params: { transfer_id: "p2p_evil", amount: 1.0, currency: "NGN", status: "completed" },
         headers: tep_headers(@other, "commerce:read"),
         as: :json
    assert_response :forbidden
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
