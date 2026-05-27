# frozen_string_literal: true

require "test_helper"

class Api::V1::Commerce::RefundsControllerTest < ActionDispatch::IntegrationTest
  test "merchant can request full refund for order" do
    owner = create_user("refund_owner")
    buyer = create_user("refund_buyer")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "ma.refund.test", display_name: "Refund Shop", status: "active")
    product = merchant.commerce_products.create!(title: "Refund Item", status: "active")
    sku = product.commerce_skus.create!(title: "Size S", price_cents: 1500, currency: "NGN")
    order = create_paid_order(merchant, buyer, sku)

    post api_v1_commerce_order_refunds_url(order.order_id),
      params: { refund: { amount_cents: 1500, reason: "customer_request" } },
      headers: tep_headers(owner, "commerce:merchant commerce:read"),
      as: :json

    assert_response :created
    assert_equal "refunded", response.parsed_body.dig("order", "status")
  end

  test "merchant can request partial refund" do
    owner = create_user("partial_owner")
    buyer = create_user("partial_buyer")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "ma.partial.test", display_name: "Partial Shop", status: "active")
    product = merchant.commerce_products.create!(title: "Partial Item", status: "active")
    sku = product.commerce_skus.create!(title: "Size L", price_cents: 3000, currency: "NGN")
    order = create_paid_order(merchant, buyer, sku)

    post api_v1_commerce_order_refunds_url(order.order_id),
      params: { refund: { amount_cents: 1500, reason: "partial_return" } },
      headers: tep_headers(owner, "commerce:merchant"),
      as: :json

    assert_response :created
    assert_equal "partially_refunded", response.parsed_body.dig("order", "status")
  end

  test "non-merchant cannot request refund" do
    owner = create_user("no_refund_owner")
    buyer = create_user("no_refund_buyer")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "ma.norefund.test", display_name: "No Refund Shop", status: "active")
    product = merchant.commerce_products.create!(title: "No Refund Item", status: "active")
    sku = product.commerce_skus.create!(title: "Size XL", price_cents: 2000, currency: "NGN")
    order = create_paid_order(merchant, buyer, sku)

    post api_v1_commerce_order_refunds_url(order.order_id),
      params: { refund: { amount_cents: 2000, reason: "customer_request" } },
      headers: tep_headers(buyer, "commerce:orders"),
      as: :json

    assert_response :forbidden
  end

  private

  def create_user(username)
    User.create!(matrix_user_id: "@#{username}:example.com", matrix_username: "#{username}:example.com", matrix_homeserver: "example.com")
  end

  def create_paid_order(merchant, buyer, sku)
    order = CommerceOrder.create!(
      commerce_merchant: merchant,
      buyer_user_id: buyer.matrix_user_id,
      payment_id: "pay_test_refund_#{SecureRandom.alphanumeric(8)}",
      status: "paid",
      subtotal_cents: sku.price_cents,
      total_cents: sku.price_cents,
      currency: sku.currency
    )
    order.commerce_order_items.create!(
      sku_id: sku.sku_id,
      product_id: sku.commerce_product.product_id,
      title: sku.title,
      quantity: 1,
      unit_price_cents: sku.price_cents,
      line_total_cents: sku.price_cents,
      currency: sku.currency
    )
    order
  end

  def tep_headers(user, scopes)
    token = TepTokenService.encode({ user_id: user.matrix_user_id, miniapp_id: "miniapp.commerce.test" }, scopes: scopes.split)
    { "Authorization" => "Bearer #{token}" }
  end
end
