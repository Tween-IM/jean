require "test_helper"

class Api::V1::Commerce::CheckoutsCallbackTest < ActionDispatch::IntegrationTest
  test "callback marks checkout and order as completed on payment success" do
    owner = create_user("callback-seller")
    buyer = create_user("callback-buyer")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "ma.callback.test", display_name: "Callback Shop", status: "active")
    product = merchant.commerce_products.create!(title: "Callback Item", status: "active")
    sku = product.commerce_skus.create!(title: "Blue", price_cents: 1_000, currency: "NGN", quantity_available: 5)
    cart = merchant.commerce_carts.create!(buyer_user_id: buyer.matrix_user_id, currency: "NGN")
    cart.commerce_cart_items.create!(commerce_sku: sku, quantity: 1)

    with_wallet_stub(:create_payment_request, { payment_id: "pay_callback_test", status: "created" }) do
      post api_v1_commerce_checkouts_url,
        params: { cart_id: cart.cart_id },
        headers: tep_headers(buyer, "commerce:checkout"),
        as: :json
    end

    checkout_id = response.parsed_body.dig("checkout", "checkout_id")
    checkout = CommerceCheckout.find_by(checkout_id: checkout_id)

    post callback_api_v1_commerce_checkouts_url,
      params: { payment_id: checkout.payment_id, status: "completed" },
      as: :json

    assert_response :success
    checkout.reload
    assert_equal "completed", checkout.status
    assert checkout.metadata.dig("callback_processed_at").present?
  end

  test "callback is idempotent" do
    owner = create_user("idempotent-callback-seller")
    buyer = create_user("idempotent-callback-buyer")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "ma.idempotent.test", display_name: "Idempotent Shop", status: "active")
    product = merchant.commerce_products.create!(title: "Idempotent Item", status: "active")
    sku = product.commerce_skus.create!(title: "Red", price_cents: 2_000, currency: "NGN", quantity_available: 3)
    cart = merchant.commerce_carts.create!(buyer_user_id: buyer.matrix_user_id, currency: "NGN")
    cart.commerce_cart_items.create!(commerce_sku: sku, quantity: 1)

    with_wallet_stub(:create_payment_request, { payment_id: "pay_idempotent_test", status: "created" }) do
      post api_v1_commerce_checkouts_url,
        params: { cart_id: cart.cart_id },
        headers: tep_headers(buyer, "commerce:checkout"),
        as: :json
    end

    checkout_id = response.parsed_body.dig("checkout", "checkout_id")
    checkout = CommerceCheckout.find_by(checkout_id: checkout_id)
    checkout.update!(status: "completed")

    post callback_api_v1_commerce_checkouts_url,
      params: { payment_id: checkout.payment_id, status: "completed" },
      as: :json

    assert_response :success
  end

  test "callback returns 404 for unknown payment" do
    post callback_api_v1_commerce_checkouts_url,
      params: { payment_id: "pay_nonexistent", status: "completed" },
      as: :json

    assert_response :not_found
  end

  private

  def create_user(username)
    User.create!(matrix_user_id: "@#{username}:example.com", matrix_username: "#{username}:example.com", matrix_homeserver: "example.com")
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
