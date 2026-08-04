require "test_helper"

class Api::V1::Commerce::ProductsControllerTest < ActionDispatch::IntegrationTest
  test "merchant can create a product with a default SKU synthesized from listing price" do
    owner = create_user("product-owner")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "miniapp.shop.test", display_name: "Shop", status: "active")

    post api_v1_commerce_products_url,
      params: {
        merchant_id: merchant.merchant_id,
        product: {
          name: "Toyota Camry 2018",
          description: "Clean interior",
          condition: "used",
          status: "active",
          media_urls: ["https://r2.example.com/photo.jpg"],
          tags: [ "Motorcycles & Scooters", "Sport" ],
          dimensions: { listing: { price: 200000.0, currency: "NGN" } }
        }
      },
      headers: tep_headers(owner, "commerce:read commerce:merchant"),
      as: :json

    assert_response :created
    body = response.parsed_body["product"]
    assert_equal "used", body["condition"]
    assert_equal "Toyota Camry 2018", body["title"]
    assert_equal({ "min" => 200000, "max" => 200000, "currency" => "NGN" }, body["price_range"])
    assert_equal 1, CommerceProduct.find_by!(product_id: body["product_id"]).commerce_skus.count
  end

  test "rejects an invalid condition value" do
    owner = create_user("product-owner-cond")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "miniapp.shop.test", display_name: "Shop", status: "active")

    post api_v1_commerce_products_url,
      params: {
        merchant_id: merchant.merchant_id,
        product: {
          name: "Toyota Camry 2018",
          condition: "fair",
          status: "active",
          dimensions: { listing: { price: 10000.0, currency: "NGN" } }
        }
      },
      headers: tep_headers(owner, "commerce:read commerce:merchant"),
      as: :json

    assert_response :unprocessable_entity
  end

  private

  def create_user(username)
    User.create!(matrix_user_id: "@#{username}:example.com", matrix_username: "#{username}:example.com", matrix_homeserver: "example.com")
  end

  def tep_headers(user, scopes)
    token = TepTokenService.encode({ user_id: user.matrix_user_id, miniapp_id: "miniapp.shop.test" }, scopes: scopes.split)
    { "Authorization" => "Bearer #{token}" }
  end
end
