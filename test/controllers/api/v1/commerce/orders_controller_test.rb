require "test_helper"

class Api::V1::Commerce::OrdersControllerTest < ActionDispatch::IntegrationTest
  test "buyer can cancel unpaid order" do
    owner = create_user("cancel_owner")
    buyer = create_user("cancel_buyer")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "ma.cancel.test", display_name: "Cancel Shop", status: "active")
    product = merchant.commerce_products.create!(title: "Cancel Item", status: "active")
    sku = product.commerce_skus.create!(title: "Size S", price_cents: 1500, currency: "NGN", quantity_available: 5)
    order = create_pending_order(merchant, buyer, sku)

    post cancel_api_v1_commerce_order_url(order.order_id),
      headers: tep_headers(buyer, "commerce:orders"),
      as: :json

    assert_response :success
    order.reload
    assert_equal "cancelled", order.status
    assert_equal "not_required", order.fulfillment_status
  end

  test "buyer cancel on paid order triggers refund" do
    owner = create_user("refund_owner")
    buyer = create_user("refund_buyer")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "ma.refund.test", display_name: "Refund Shop", status: "active")
    product = merchant.commerce_products.create!(title: "Refund Item", status: "active")
    sku = product.commerce_skus.create!(title: "Size M", price_cents: 2000, currency: "NGN", quantity_available: 5)
    order = create_paid_order(merchant, buyer, sku)

    with_wallet_stub(:refund_payment, { "refund_id" => "ref_cancel_test", "status" => "refunded" }) do
      post cancel_api_v1_commerce_order_url(order.order_id),
        headers: tep_headers(buyer, "commerce:orders"),
        as: :json
    end

    assert_response :success
    order.reload
    assert_equal "refunded", order.status
    assert_equal true, order.metadata["inventory_restored"]
  end

  test "buyer cancel on paid order fails when refund fails" do
    owner = create_user("failrefund_owner")
    buyer = create_user("failrefund_buyer")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "ma.failrefund.test", display_name: "FailRefund Shop", status: "active")
    product = merchant.commerce_products.create!(title: "FailRefund Item", status: "active")
    sku = product.commerce_skus.create!(title: "Size L", price_cents: 3000, currency: "NGN", quantity_available: 5)
    order = create_paid_order(merchant, buyer, sku)

    with_wallet_stub(:refund_payment, {}) do
      post cancel_api_v1_commerce_order_url(order.order_id),
        headers: tep_headers(buyer, "commerce:orders"),
        as: :json
    end

    assert_response :unprocessable_entity
    order.reload
    assert_equal "paid", order.status
  end

  test "buyer cannot cancel another buyers order" do
    owner = create_user("forbidden_owner")
    buyer = create_user("forbidden_buyer")
    other = create_user("other_buyer")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "ma.forbidden.test", display_name: "Forbidden Shop", status: "active")
    product = merchant.commerce_products.create!(title: "Forbidden Item", status: "active")
    sku = product.commerce_skus.create!(title: "Size XL", price_cents: 1000, currency: "NGN")
    order = create_pending_order(merchant, buyer, sku)

    post cancel_api_v1_commerce_order_url(order.order_id),
      headers: tep_headers(other, "commerce:orders"),
      as: :json

    assert_response :forbidden
  end

  private

  def create_user(username)
    User.create!(matrix_user_id: "@#{username}:example.com", matrix_username: "#{username}:example.com", matrix_homeserver: "example.com")
  end

  def create_pending_order(merchant, buyer, sku)
    order = CommerceOrder.create!(
      commerce_merchant: merchant,
      buyer_user_id: buyer.matrix_user_id,
      payment_id: "pay_test_pending_#{SecureRandom.alphanumeric(8)}",
      status: "pending_payment",
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

  def create_paid_order(merchant, buyer, sku)
    order = CommerceOrder.create!(
      commerce_merchant: merchant,
      buyer_user_id: buyer.matrix_user_id,
      payment_id: "pay_test_paid_#{SecureRandom.alphanumeric(8)}",
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

  def with_wallet_stub(method_name, response)
    original = WalletService.method(method_name)
    WalletService.define_singleton_method(method_name) { |*, **| response }
    yield
  ensure
    WalletService.define_singleton_method(method_name, original)
  end
end
