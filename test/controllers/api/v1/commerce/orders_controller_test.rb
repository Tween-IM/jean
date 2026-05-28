# frozen_string_literal: true

require "test_helper"

class Api::V1::Commerce::OrdersControllerTest < ActionDispatch::IntegrationTest
  test "buyer can view their own order" do
    owner = create_user("order_owner")
    buyer = create_user("order_buyer")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "ma.order.test", display_name: "Order Shop", status: "active")
    product = merchant.commerce_products.create!(title: "Order Item", status: "active")
    sku = product.commerce_skus.create!(title: "Size M", price_cents: 2500, currency: "NGN")
    order = CommerceOrder.create!(
      commerce_merchant: merchant,
      buyer_user_id: buyer.matrix_user_id,
      payment_id: "pay_order_buyer_#{SecureRandom.alphanumeric(8)}",
      status: "paid",
      subtotal_cents: 2500,
      total_cents: 2500,
      currency: "NGN"
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

    get api_v1_commerce_order_url(order.order_id),
      headers: tep_headers(buyer, "commerce:orders"),
      as: :json

    assert_response :success
    assert_equal order.order_id, response.parsed_body.dig("order", "order_id")
    assert_equal "paid", response.parsed_body.dig("order", "status")
  end

  test "merchant can view their own order" do
    owner = create_user("merchant_view")
    buyer = create_user("merchant_buyer")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "ma.mv.test", display_name: "MV Shop", status: "active")
    product = merchant.commerce_products.create!(title: "MV Item", status: "active")
    sku = product.commerce_skus.create!(title: "Size S", price_cents: 3500, currency: "NGN")
    order = CommerceOrder.create!(
      commerce_merchant: merchant,
      buyer_user_id: buyer.matrix_user_id,
      payment_id: "pay_mv_#{SecureRandom.alphanumeric(8)}",
      status: "paid",
      subtotal_cents: 3500,
      total_cents: 3500,
      currency: "NGN"
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

    get api_v1_commerce_order_url(order.order_id),
      headers: tep_headers(owner, "commerce:merchant commerce:orders"),
      as: :json

    assert_response :success
    assert_equal order.order_id, response.parsed_body.dig("order", "order_id")
  end

  test "third party cannot view order" do
    owner = create_user("no_view_owner")
    buyer = create_user("no_view_buyer")
    other = create_user("no_view_other")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "ma.noview.test", display_name: "No View Shop", status: "active")
    product = merchant.commerce_products.create!(title: "NV Item", status: "active")
    sku = product.commerce_skus.create!(title: "Size L", price_cents: 4500, currency: "NGN")
    order = CommerceOrder.create!(
      commerce_merchant: merchant,
      buyer_user_id: buyer.matrix_user_id,
      payment_id: "pay_noview_#{SecureRandom.alphanumeric(8)}",
      status: "paid",
      subtotal_cents: 4500,
      total_cents: 4500,
      currency: "NGN"
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

    get api_v1_commerce_order_url(order.order_id),
      headers: tep_headers(other, "commerce:orders"),
      as: :json

    assert_response :forbidden
  end

  private

  def create_user(username)
    User.create!(matrix_user_id: "@#{username}:example.com", matrix_username: "#{username}:example.com", matrix_homeserver: "example.com")
  end

  def tep_headers(user, scopes)
    token = TepTokenService.encode({ user_id: user.matrix_user_id, miniapp_id: "miniapp.commerce.test" }, scopes: scopes.split)
    { "Authorization" => "Bearer #{token}" }
  end
end
