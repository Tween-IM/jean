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

    post api_v1_commerce_checkouts_url,
      params: { cart_id: cart.cart_id, checkout: { shipping_address: { city: "Lagos" } } },
      headers: tep_headers(buyer, "commerce:checkout"),
      as: :json

    assert_response :created
    assert_equal "payment_pending", response.parsed_body.dig("checkout", "status")
    assert_equal 5_000, response.parsed_body.dig("order", "total_cents")
    assert_equal sku.sku_id, response.parsed_body.dig("order", "items", 0, "sku_id")
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
end
