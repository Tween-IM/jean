require "test_helper"

class Api::V1::Commerce::CheckoutsControllerTest < ActionDispatch::IntegrationTest
  test "buyer can checkout a standalone commerce cart and receive an order" do
    owner = create_user("seller")
    buyer = create_user("buyer")
    merchant = CommerceMerchant.create!(
      owner_user_id: owner.matrix_user_id,
      miniapp_id: "miniapp.shop.test",
      display_name: "Demo Shop",
      status: "active"
    )
    product = merchant.commerce_products.create!(title: "Canvas Tote", status: "active")
    sku = product.commerce_skus.create!(title: "Black", price_cents: 2_500, currency: "NGN", quantity_available: 10)
    cart = merchant.commerce_carts.create!(buyer_user_id: buyer.matrix_user_id, currency: "NGN")
    cart.commerce_cart_items.create!(commerce_sku: sku, quantity: 2)
    with_wallet_stub(:create_payment_request, { payment_id: "pay_checkout_test", status: "created" }) do

      post api_v1_commerce_checkouts_url,
        params: { cart_id: cart.cart_id, checkout: { shipping_address: { city: "Lagos" } } },
        headers: tep_headers(buyer, "commerce:checkout"),
        as: :json
    end

    assert_response :created
    assert_equal "payment_pending", response.parsed_body.dig("checkout", "status")
    assert_equal "pay_checkout_test", response.parsed_body.dig("checkout", "payment_id")
    assert_equal 5_000, response.parsed_body.dig("order", "total_cents")
    assert_equal sku.sku_id, response.parsed_body.dig("order", "items", 0, "sku_id")
    assert_equal 8, sku.reload.quantity_available
  end

  test "buyer can authorize checkout payment and mark order paid" do
    owner = create_user("paid-seller")
    buyer = create_user("paid-buyer")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "miniapp.shop.test", display_name: "Paid Shop", status: "active")
    product = merchant.commerce_products.create!(title: "Cap", status: "active")
    sku = product.commerce_skus.create!(title: "Blue", price_cents: 1_000, currency: "NGN", quantity_available: 5)
    cart = merchant.commerce_carts.create!(buyer_user_id: buyer.matrix_user_id, currency: "NGN")
    cart.commerce_cart_items.create!(commerce_sku: sku, quantity: 1)

    with_wallet_stub(:create_payment_request, { payment_id: "pay_auth_test", status: "created" }) do
      post api_v1_commerce_checkouts_url,
        params: { cart_id: cart.cart_id },
        headers: tep_headers(buyer, "commerce:checkout"),
        as: :json
    end
    checkout_id = response.parsed_body.dig("checkout", "checkout_id")

    with_wallet_stub(:authorize_payment, { "status" => "completed", "txn_id" => "txn_auth_test" }) do
      post authorize_api_v1_commerce_checkout_url(checkout_id),
        params: { authorization: { signature: "sig", device_id: "device" } },
        headers: tep_headers(buyer, "commerce:checkout"),
        as: :json
    end

    assert_response :success
    assert_equal "completed", response.parsed_body.dig("checkout", "status")
    assert_equal "paid", response.parsed_body.dig("order", "status")
  end

  test "buyer can cancel checkout and restore reserved inventory" do
    owner = create_user("cancel-seller")
    buyer = create_user("cancel-buyer")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "miniapp.shop.test", display_name: "Cancel Shop", status: "active")
    product = merchant.commerce_products.create!(title: "Bottle", status: "active")
    sku = product.commerce_skus.create!(title: "Green", price_cents: 1_500, currency: "NGN", quantity_available: 3)
    cart = merchant.commerce_carts.create!(buyer_user_id: buyer.matrix_user_id, currency: "NGN")
    cart.commerce_cart_items.create!(commerce_sku: sku, quantity: 2)

    with_wallet_stub(:create_payment_request, { payment_id: "pay_cancel_test", status: "created" }) do
      post api_v1_commerce_checkouts_url,
        params: { cart_id: cart.cart_id },
        headers: tep_headers(buyer, "commerce:checkout"),
        as: :json
    end
    assert_equal 1, sku.reload.quantity_available
    checkout_id = response.parsed_body.dig("checkout", "checkout_id")

    post cancel_api_v1_commerce_checkout_url(checkout_id),
      headers: tep_headers(buyer, "commerce:checkout"),
      as: :json

    assert_response :success
    assert_equal "cancelled", response.parsed_body.dig("checkout", "status")
    assert_equal 3, sku.reload.quantity_available
    assert_equal true, response.parsed_body.dig("order", "metadata", "inventory_restored")
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
    token = TepTokenService.encode({ user_id: user.matrix_user_id, miniapp_id: "miniapp.shop.test" }, scopes: scopes.split)
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
