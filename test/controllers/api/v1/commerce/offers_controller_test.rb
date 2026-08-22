require "test_helper"

class Api::V1::Commerce::OffersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @seller = create_user("offer_seller")
    @buyer = create_user("offer_buyer")
    @merchant = CommerceMerchant.create!(
      owner_user_id: @seller.matrix_user_id,
      miniapp_id: "ma.offer.test",
      display_name: "Offer Shop",
      status: "active"
    )
    @product = @merchant.commerce_products.create!(
      title: "Offer Product",
      status: "active",
      condition: "new",
      store_type: "marketplace"
    )
    @conversation = CommerceConversation.create!(
      buyer_user_id: @buyer.matrix_user_id,
      product_id: @product.product_id,
      status: "open"
    )
  end

  test "creates an offer with float cent values" do
    post api_v1_commerce_conversation_offers_url(@conversation.conversation_id),
      params: { offer: {
        offer_type: "product",
        currency: "NGN",
        subtotal_cents: 5000.0,
        delivery_fee_cents: 500.0,
        total_cents: 5500.0,
        terms: { product_id: @product.product_id, quantity: 1 }
      } },
      headers: tep_headers(@seller, "commerce:write"),
      as: :json

    assert_response :created
    offer = JSON.parse(response.body).dig("offer")
    assert_equal 5500, offer["total_cents"]
    assert_equal 5000, offer["subtotal_cents"]
    assert_equal 500, offer["delivery_fee_cents"]
    assert_equal "proposed", offer["status"]
  end

  private

  def create_user(username)
    User.create!(matrix_user_id: "@#{username}:tween.im", matrix_username: "#{username}:tween.im",
                 matrix_homeserver: "tween.im")
  end

  def tep_headers(user, scopes)
    token = TepTokenService.encode({ user_id: user.matrix_user_id, miniapp_id: "miniapp.commerce.test" },
                                   scopes: scopes.split)
    { "Authorization" => "Bearer #{token}" }
  end
end
