require "test_helper"
require "minitest/mock"
require "json"

# End-to-end journey for a conversation-led protected deal across Jean and the
# Tween Pay contract:
#
#   offer proposed → accepted (protected payment created)
#   → buyer funds → seller ships → carrier delivers → buyer confirms
#   → inspection started (release scheduled)
#   → Tween Pay outbox callback "protected_payment.released"
#   → order fulfilled, protection completed, Matrix events published
#
# The Tween Pay side is exercised for real in tween-pay's own request specs;
# here we stub its internal endpoints with the exact response shapes Tween Pay
# returns and replay its signed outbox callback through the callback consumer.
class ProtectedCommerceE2ETest < ActionDispatch::IntegrationTest
  setup do
    @_matrix_as_token = ENV["MATRIX_AS_TOKEN"]
    ENV["MATRIX_AS_TOKEN"] = nil
    @seller = create_user("e2e_seller")
    @buyer = create_user("e2e_buyer")
    @merchant = CommerceMerchant.create!(
      owner_user_id: @seller.matrix_user_id,
      miniapp_id: "ma.e2e.test",
      display_name: "E2E Shop",
      status: "active",
      wallet_id: "wallet_e2e",
      commission_rate: 5
    )
    @product = @merchant.commerce_products.create!(
      title: "E2E Gadget",
      status: "active",
      condition: "new",
      store_type: "marketplace"
    )
    @sku = @product.commerce_skus.create!(
      title: "Default", price_cents: 100_000, currency: "NGN", quantity_available: 10
    )
    @conversation = CommerceConversation.create!(
      buyer_user_id: @buyer.matrix_user_id,
      product_id: @product.product_id,
      status: "open"
    )
    @conversation.update!(matrix_room_id: "!e2e_room:tween.im")
  end

  teardown do
    ENV["MATRIX_AS_TOKEN"] = @_matrix_as_token
  end

  test "full protected deal journey ends in released and completed" do
    # 1. Seller proposes an offer
    post api_v1_commerce_conversation_offers_url(@conversation.conversation_id),
      params: { offer: {
        offer_type: "product", currency: "NGN",
        subtotal_cents: 100_000, delivery_fee_cents: 5_000, total_cents: 105_000,
        terms: { product_id: @product.product_id, quantity: 1, delivery_method: "shipment" }
      } },
      headers: tep_headers(@seller, "commerce:write"),
      as: :json
    assert_response :created
    offer_id = JSON.parse(response.body).dig("offer", "offer_id")
    assert_equal 105_000, JSON.parse(response.body).dig("offer", "total_cents")

    # 2. Buyer accepts → protected order + payment created
    stub_protected(:create_payment, {
      protected_payment: {
        protected_payment_id: "ppay_e2e_1", order_id: "ord_e2e_1",
        status: "payment_pending", gross_amount_cents: 105_000
      }
    }) do
      post accept_api_v1_commerce_offer_url(offer_id),
        headers: tep_headers(@buyer, "commerce:write"), as: :json
    end
    assert_response :success
    body = JSON.parse(response.body)
    order_id = body.dig("order", "order_id")
    assert_equal "conversation", body.dig("order", "source")
    assert_equal "active", body.dig("order", "protection_status")

    order = CommerceOrder.find_by!(order_id: order_id)
    assert_equal "ppay_e2e_1", order.protected_payment_id

    # 3. Buyer funds from wallet
    stub_protected(:fund, { protected_payment: { status: "funded" } }) do
      post fund_api_v1_commerce_order_url(order_id),
        headers: tep_headers(@buyer, "commerce:orders"), as: :json
    end
    assert_response :success
    assert_equal "paid", order.reload.status
    assert_equal "active", order.reload.protection_status

    # 4. Seller ships with tracking
    post api_v1_commerce_order_fulfillment_url(order_id),
      params: { fulfillment: { carrier: "GIG", tracking_number: "GIG-77" } },
      headers: tep_headers(@seller, "commerce:merchant"), as: :json
    assert_response :success
    fulfillment = order.reload.commerce_fulfillments.first
    assert_equal "shipped", fulfillment.status

    # 5. Carrier delivers (integrated logistics webhook — not the seller)
    fulfillment.update!(status: "delivered", delivered_at: Time.current)

    # 6. Buyer confirms delivery → inspection starts, release scheduled
    stub_protected(:schedule_release, {
      protected_payment: { status: "release_scheduled" }
    }) do
      post confirm_delivery_api_v1_commerce_order_url(order_id),
        headers: tep_headers(@buyer, "commerce:orders"), as: :json
    end
    assert_response :success
    assert_equal "fulfilled", order.reload.status
    assert_equal "accepted", fulfillment.reload.status
    assert order.reload.metadata["confirmed_at"].present?

    # 7. Tween Pay release worker posts outbox event; Jean callback consumer applies it
    replay_tween_pay_callback(
      event_type: "protected_payment.released",
      protected_payment_id: "ppay_e2e_1",
      data: {
        protected_payment_id: "ppay_e2e_1", order_id: order_id,
        status: "released", currency: "NGN",
        gross_amount_cents: 105_000, released_amount_cents: 105_000,
        refunded_amount_cents: 0, actor: "release_worker",
        amount_cents: 105_000, net_to_seller_cents: 99_750,
        commission_cents: 5_250, occurred_at: Time.current.iso8601
      }
    )

    assert_equal "fulfilled", order.reload.status
    assert_equal "completed", order.reload.protection_status
    assert order.reload.metadata["released_at"].present?

    # 8. Duplicate callback is idempotent
    replay_tween_pay_callback(
      event_type: "protected_payment.released",
      protected_payment_id: "ppay_e2e_1",
      data: { protected_payment_id: "ppay_e2e_1", order_id: order_id, status: "released" }
    )
    assert_equal "fulfilled", order.reload.status
  end

  test "refund callback marks the order refunded" do
    order = create_funded_order

    replay_tween_pay_callback(
      event_type: "protected_payment.refunded",
      protected_payment_id: order.protected_payment_id,
      data: {
        protected_payment_id: order.protected_payment_id, order_id: order.order_id,
        status: "refunded", currency: "NGN",
        gross_amount_cents: 105_000, released_amount_cents: 0,
        refunded_amount_cents: 105_000, total_refunded_cents: 105_000,
        actor: "buyer_cancelled", occurred_at: Time.current.iso8601
      }
    )

    assert_equal "refunded", order.reload.status
    assert_equal "completed", order.reload.protection_status
  end

  test "callback with a bad signature is rejected" do
    order = create_funded_order

    body = {
      event_id: "obx_bad", event_type: "protected_payment.released",
      aggregate_type: "protected_payment", aggregate_id: order.protected_payment_id,
      data: { protected_payment_id: order.protected_payment_id }
    }.to_json

    ENV["JEAN_CALLBACK_SECRET"] = "correct-secret"
    post "/api/v1/commerce/callbacks/tween_pay",
      params: body,
      headers: { "Content-Type" => "application/json",
                 "X-Tween-Signature" => "sha256=" + OpenSSL::HMAC.hexdigest("sha256", "wrong-secret", body) }
    assert_response :unauthorized
    assert_equal "paid", order.reload.status
  ensure
    ENV.delete("JEAN_CALLBACK_SECRET")
  end

  private

  def create_funded_order
    order = CommerceOrder.create!(
      commerce_merchant: @merchant,
      buyer_user_id: @buyer.matrix_user_id,
      payment_id: "ppay_e2e_#{SecureRandom.alphanumeric(6)}",
      status: "paid",
      source: "conversation",
      protection_status: "active",
      protected_payment_id: "ppay_e2e_#{SecureRandom.alphanumeric(6)}",
      total_cents: 105_000,
      currency: "NGN",
      metadata: { conversation_id: @conversation.conversation_id }
    )
    order
  end

  def replay_tween_pay_callback(event_type:, protected_payment_id:, data:)
    body = {
      event_id: "obx_#{SecureRandom.alphanumeric(12).downcase}",
      event_type: event_type,
      aggregate_type: "protected_payment",
      aggregate_id: protected_payment_id,
      data: data
    }.to_json

    ENV["JEAN_CALLBACK_SECRET"] = "e2e-callback-secret"
    signature = "sha256=" + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), "e2e-callback-secret", body)
    post "/api/v1/commerce/callbacks/tween_pay",
      params: body,
      headers: { "Content-Type" => "application/json",
                 "X-Tween-Signature" => signature,
                 "X-Tween-Event-ID" => JSON.parse(body)["event_id"] }
    assert_response :success
  ensure
    ENV.delete("JEAN_CALLBACK_SECRET")
  end

  def stub_protected(method_name, response)
    ProtectedCommerceService.stub(method_name, response) do
      yield
    end
  end

  def create_user(username)
    User.create!(matrix_user_id: "@#{username}:tween.im", matrix_username: "#{username}:tween.im",
                 matrix_homeserver: "tween.im")
  end

  def tep_headers(user, scopes)
    token = TepTokenService.encode({ user_id: user.matrix_user_id, miniapp_id: "miniapp.commerce.e2e" },
                                   scopes: scopes.split)
    { "Authorization" => "Bearer #{token}" }
  end
end
