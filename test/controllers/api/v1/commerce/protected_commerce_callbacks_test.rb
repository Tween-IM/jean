require "test_helper"

class Api::V1::Commerce::ProtectedCommerceCallbacksTest < ActionDispatch::IntegrationTest
  setup do
    @callback_secret = "test_callback_secret_#{SecureRandom.hex(16)}"
    ENV["JEAN_CALLBACK_SECRET"] = @callback_secret
  end

  teardown do
    ENV.delete("JEAN_CALLBACK_SECRET")
  end

  test "released callback creates payout record" do
    owner = create_user("callback-seller")
    buyer = create_user("callback-buyer")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "ma.callback.test", display_name: "Callback Shop", status: "active")
    product = merchant.commerce_products.create!(title: "Callback Item", status: "active")
    sku = product.commerce_skus.create!(title: "Blue", price_cents: 10_000, currency: "NGN", quantity_available: 5)
    order = create_order(merchant, buyer, sku)

    # Simulate tween-pay release callback with HMAC signature
    body = {
      event_id: "evt_release_test_1",
      event_type: "protected_payment.released",
      data: {
        protected_payment_id: order.protected_payment_id,
        seller_proceeds_cents: 9_500,
        released_amount_cents: 10_000
      }
    }

    post api_v1_commerce_callback_url,
      params: body,
      headers: callback_headers(body),
      as: :json

    assert_response :success
    order.reload
    assert_equal "fulfilled", order.status
    assert_equal "completed", order.protection_status

    # Verify payout was created
    payout = CommercePayout.find_by(order_id: order.order_id, payout_method: "protected_release")
    assert payout.present?, "Expected payout record for released order"
    assert_equal 9_500, payout.amount_cents
    assert_equal "NGN", payout.currency
    assert_equal "completed", payout.status
    assert_equal order.order_id, payout.order_id
    assert_equal 10_000, payout.metadata["gross_amount_cents"]
    assert_equal 500, payout.metadata["commission_cents"]
    assert payout.completed_at.present?
  end

  test "released callback is idempotent — duplicate event_id does not create duplicate payout" do
    owner = create_user("idempotent-release")
    buyer = create_user("idempotent-release-buyer")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "ma.idempotent.release", display_name: "Idempotent Release Shop", status: "active")
    product = merchant.commerce_products.create!(title: "Idempotent Item", status: "active")
    sku = product.commerce_skus.create!(title: "Green", price_cents: 5_000, currency: "NGN", quantity_available: 3)
    order = create_order(merchant, buyer, sku)

    # First event creates the payout
    body1 = {
      event_id: "evt_release_idempotent",
      event_type: "protected_payment.released",
      data: { protected_payment_id: order.protected_payment_id, seller_proceeds_cents: 4_750 }
    }
    post api_v1_commerce_callback_url, params: body1, headers: callback_headers(body1), as: :json
    assert_response :success

    # Duplicate event — dedupe_record should prevent reprocessing
    body2 = {
      event_id: "evt_release_idempotent",
      event_type: "protected_payment.released",
      data: { protected_payment_id: order.protected_payment_id, seller_proceeds_cents: 4_750 }
    }
    post api_v1_commerce_callback_url, params: body2, headers: callback_headers(body2), as: :json
    # Controller returns 422 on duplicate event_id (RecordInvalid from dedupe_event)
    assert_response :unprocessable_entity

    # Only one payout should be created
    payouts = CommercePayout.where(order_id: order.order_id, payout_method: "protected_release")
    assert_equal 1, payouts.count
  end

  test "refunded callback creates reversal payout" do
    owner = create_user("refund-seller")
    buyer = create_user("refund-buyer")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "ma.refund.test", display_name: "Refund Shop", status: "active")
    product = merchant.commerce_products.create!(title: "Refund Item", status: "active")
    sku = product.commerce_skus.create!(title: "Red", price_cents: 8_000, currency: "NGN", quantity_available: 5)
    order = create_order(merchant, buyer, sku)

    body = {
      event_id: "evt_refund_test_1",
      event_type: "protected_payment.refunded",
      data: {
        protected_payment_id: order.protected_payment_id,
        total_refunded_cents: 8_000,
        reason: "not_as_described"
      }
    }

    post api_v1_commerce_callback_url,
      params: body,
      headers: callback_headers(body),
      as: :json

    assert_response :success

    # Verify reversal payout was created
    payout = CommercePayout.find_by(order_id: order.order_id, payout_method: "refund")
    assert payout.present?, "Expected reversal payout for refunded order"
    assert_equal 8_000, payout.amount_cents
    assert_equal "completed", payout.status
    assert_equal "not_as_described", payout.metadata["reason"]
  end

  private

  def create_user(username)
    User.create!(matrix_user_id: "@#{username}:example.com", matrix_username: "#{username}:example.com", matrix_homeserver: "example.com")
  end

  def create_order(merchant, buyer, sku)
    order = CommerceOrder.create!(
      commerce_merchant: merchant,
      buyer_user_id: buyer.matrix_user_id,
      payment_id: "ppay_test_#{SecureRandom.hex(8)}",
      protected_payment_id: "ppay_test_#{SecureRandom.hex(8)}",
      status: "paid",
      protection_status: "active",
      subtotal_cents: sku.price_cents,
      total_cents: sku.price_cents,
      currency: "NGN",
      fulfillment_type: "shipment"
    )
    order.commerce_order_items.create!(
      sku_id: sku.sku_id,
      product_id: sku.commerce_product.product_id,
      title: sku.title,
      product_name: sku.commerce_product.title,
      quantity: 1,
      unit_price_cents: sku.price_cents,
      line_total_cents: sku.price_cents,
      currency: "NGN"
    )
    order
  end

  def api_v1_commerce_callback_url
    "/api/v1/commerce/callbacks/tween_pay"
  end

  def callback_headers(body)
    body_json = body.to_json
    signature = "sha256=" + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), @callback_secret, body_json)
    {
      "X-Tween-Signature" => signature,
      "X-Tween-Event-ID" => body[:event_id],
      "Content-Type" => "application/json"
    }
  end
end
