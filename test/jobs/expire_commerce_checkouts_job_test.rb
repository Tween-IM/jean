require "test_helper"

class ExpireCommerceCheckoutsJobTest < ActiveJob::TestCase
  test "expires pending checkout and restores reserved inventory" do
    owner = create_user("expiry-seller")
    buyer = create_user("expiry-buyer")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "miniapp.shop.test", display_name: "Expiry Shop", status: "active")
    product = merchant.commerce_products.create!(title: "Bottle", status: "active")
    sku = product.commerce_skus.create!(title: "Amber", price_cents: 1_000, currency: "NGN", quantity_available: 1)
    cart = merchant.commerce_carts.create!(buyer_user_id: buyer.matrix_user_id, currency: "NGN", status: "checked_out")
    checkout = CommerceCheckout.create!(
      commerce_cart: cart,
      commerce_merchant: merchant,
      buyer_user_id: buyer.matrix_user_id,
      payment_id: "pay_expiring",
      status: "payment_pending",
      expires_at: 1.minute.ago,
      metadata: { "inventory_reserved" => true }
    )
    order = merchant.commerce_orders.create!(
      buyer_user_id: buyer.matrix_user_id,
      payment_id: checkout.payment_id,
      status: "pending_payment",
      total_cents: 1_000,
      currency: "NGN",
      metadata: { "checkout_id" => checkout.checkout_id }
    )
    order.commerce_order_items.create!(sku_id: sku.sku_id, product_id: product.product_id, title: sku.title, quantity: 2, unit_price_cents: 1_000, line_total_cents: 2_000, currency: "NGN")
    checkout.update!(order_id: order.order_id)
    sku.update!(quantity_available: 0)

    ExpireCommerceCheckoutsJob.perform_now

    assert_equal "expired", checkout.reload.status
    assert_equal "cancelled", order.reload.status
    assert_equal "abandoned", cart.reload.status
    assert_equal 2, sku.reload.quantity_available
    assert_equal true, order.metadata["inventory_restored"]
  end

  private

  def create_user(username)
    User.create!(matrix_user_id: "@#{username}:example.com", matrix_username: "#{username}:example.com", matrix_homeserver: "example.com")
  end
end
