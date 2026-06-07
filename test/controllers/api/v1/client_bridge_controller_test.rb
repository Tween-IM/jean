# frozen_string_literal: true

require "test_helper"

class Api::V1::ClientBridgeControllerTest < ActionDispatch::IntegrationTest
  test "tween.social.openVideo returns deep link" do
    user = create_user("bridge_user")
    video = SocialPost.create!(
      post_id: "vid_bridge_test",
      creator_user_id: user.matrix_user_id,
      media_upload_id: "upl_bridge",
      status: "published"
    )

    post api_v1_client_bridge_url,
      params: { jsonrpc: "2.0", method: "tween.social.openVideo", params: { video_id: video.post_id }, id: 1 },
      headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{tep_token(user, "social:read")}" },
      as: :json

    assert_response :success
    assert_equal "2.0", response.parsed_body["jsonrpc"]
    assert_equal video.post_id, response.parsed_body["result"]["video_id"]
    assert_match(/tween:\/\/social\/video/, response.parsed_body["result"]["deep_link"])
  end

  test "tween.social.shareVideo shares to room" do
    user = create_user("share_user")
    creator = create_user("share_creator")
    video = SocialPost.create!(
      post_id: "vid_share_test",
      creator_user_id: creator.matrix_user_id,
      media_upload_id: "upl_share",
      status: "published"
    )

    post api_v1_client_bridge_url,
      params: { jsonrpc: "2.0", method: "tween.social.shareVideo", params: { video_id: video.post_id, room_id: "!room:tween.example" }, id: 2 },
      headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{tep_token(user, "social:engage")}" },
      as: :json

    assert_response :success
    assert_equal true, response.parsed_body["result"]["shared"]
    assert_equal "!room:tween.example", response.parsed_body["result"]["room_id"]
  end

  test "tween.commerce.openProduct returns deep link" do
    user = create_user("product_user")
    owner = create_user("product_owner")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "ma.test", display_name: "Test Shop", status: "active")
    product = CommerceProduct.create!(commerce_merchant: merchant, title: "Test Product", status: "active")

    post api_v1_client_bridge_url,
      params: { jsonrpc: "2.0", method: "tween.commerce.openProduct", params: { product_id: product.product_id }, id: 3 },
      headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{tep_token(user, "commerce:read")}" },
      as: :json

    assert_response :success
    assert_equal product.product_id, response.parsed_body["result"]["product_id"]
    assert_match(/tween:\/\/commerce\/product/, response.parsed_body["result"]["deep_link"])
  end

  test "tween.commerce.startCheckout returns owned cart deep link" do
    user = create_user("co_user")
    owner = create_user("co_owner")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "ma.test", display_name: "CO Shop", status: "active")
    product = merchant.commerce_products.create!(title: "Item", status: "active")
    sku = product.commerce_skus.create!(title: "Size M", price_cents: 1000, currency: "NGN")
    cart = merchant.commerce_carts.create!(buyer_user_id: user.matrix_user_id, currency: "NGN")
    cart.commerce_cart_items.create!(commerce_sku: sku, quantity: 1)

    post api_v1_client_bridge_url,
      params: { jsonrpc: "2.0", method: "tween.commerce.startCheckout", params: { cart_id: cart.cart_id }, id: 4 },
      headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{tep_token(user, "commerce:checkout")}" },
      as: :json

    assert_response :success
    assert_equal cart.cart_id, response.parsed_body["result"]["cart_id"]
    assert_match(/tween:\/\/commerce\/checkout/, response.parsed_body["result"]["deep_link"])
  end

  test "tween.commerce.startCheckout rejects another buyer cart" do
    user = create_user("co_intruder")
    buyer = create_user("co_buyer")
    owner = create_user("co_guard_owner")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "ma.test", display_name: "Guard Shop", status: "active")
    cart = merchant.commerce_carts.create!(buyer_user_id: buyer.matrix_user_id, currency: "NGN")

    post api_v1_client_bridge_url,
      params: { jsonrpc: "2.0", method: "tween.commerce.startCheckout", params: { cart_id: cart.cart_id }, id: 7 },
      headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{tep_token(user, "commerce:checkout")}" },
      as: :json

    assert_response :forbidden
    assert_equal -32003, response.parsed_body["error"]["code"]
  end

  test "returns json-rpc forbidden when scope is missing" do
    user = create_user("scope_user")

    post api_v1_client_bridge_url,
      params: { jsonrpc: "2.0", method: "tween.social.createPost", params: {}, id: 8 },
      headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{tep_token(user, "social:read")}" },
      as: :json

    assert_response :forbidden
    assert_equal -32003, response.parsed_body["error"]["code"]
    assert_includes response.parsed_body["error"]["message"], "social:write"
  end

  test "returns error for unknown method" do
    user = create_user("unknown_user")

    post api_v1_client_bridge_url,
      params: { jsonrpc: "2.0", method: "tween.unknown.method", params: {}, id: 5 },
      headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{tep_token(user, "social:read")}" },
      as: :json

    assert_response :bad_request
    assert_equal -32601, response.parsed_body["error"]["code"]
    assert_includes response.parsed_body["error"]["message"], "Method not found"
  end

  test "returns error for missing required params" do
    user = create_user("missing_user")

    post api_v1_client_bridge_url,
      params: { jsonrpc: "2.0", method: "tween.social.openVideo", params: {}, id: 6 },
      headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{tep_token(user, "social:read")}" },
      as: :json

    assert_response :bad_request
    assert_equal -32602, response.parsed_body["error"]["code"]
    assert_includes response.parsed_body["error"]["message"], "video_id required"
  end

  private

  def create_user(username)
    User.create!(matrix_user_id: "@#{username}:example.com", matrix_username: "#{username}:example.com", matrix_homeserver: "example.com")
  end

  def tep_token(user, scope)
    TepTokenService.encode({ user_id: user.matrix_user_id, miniapp_id: "miniapp.test" }, scopes: scope.split)
  end
end
