require "test_helper"

class Api::V1::Commerce::CartsControllerTest < ActionDispatch::IntegrationTest
  test "buyer receives shipping quotes available for their destination" do
    owner = create_user("quote-seller")
    buyer = create_user("quote-buyer")
    merchant = CommerceMerchant.create!(
      owner_user_id: owner.matrix_user_id,
      miniapp_id: "miniapp.shop.test",
      display_name: "Quote Shop",
      status: "active"
    )
    merchant.commerce_shipping_profiles.create!(
      name: "Lagos delivery",
      processing_time_days: 1,
      zones: [
        {
          name: "Lagos",
          countries: [ "NG" ],
          states: [ "Lagos" ],
          rate_cents: 150_000,
          transit_days: 2,
          currency: "NGN"
        }
      ]
    )
    cart = merchant.commerce_carts.create!(
      buyer_user_id: buyer.matrix_user_id,
      currency: "NGN"
    )

    post shipping_quotes_api_v1_commerce_cart_url(cart.cart_id),
      params: { country: "NG", state: "Lagos" },
      headers: tep_headers(buyer, "commerce:cart"),
      as: :json

    assert_response :success
    quote = response.parsed_body.fetch("shipping_quotes").first
    assert_equal "Lagos delivery", quote.fetch("name")
    assert_equal 150_000, quote.fetch("rate_cents")
    assert_equal 3, quote.fetch("delivery_days")
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
    token = TepTokenService.encode(
      { user_id: user.matrix_user_id, miniapp_id: "miniapp.shop.test" },
      scopes: scopes.split
    )
    { "Authorization" => "Bearer #{token}" }
  end
end
