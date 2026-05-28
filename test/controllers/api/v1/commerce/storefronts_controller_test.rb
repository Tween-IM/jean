require "test_helper"

class Api::V1::Commerce::StorefrontsControllerTest < ActionDispatch::IntegrationTest
  test "merchant can create and update a storefront" do
    owner = create_user("storefront-owner")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "miniapp.shop.test", display_name: "Shop", status: "active")

    post api_v1_commerce_storefronts_url,
      params: { merchant_id: merchant.merchant_id, storefront: { display_name: "Main Shop", description: "Daily drops", status: "published" } },
      headers: tep_headers(owner, "commerce:read commerce:merchant"),
      as: :json

    assert_response :created
    storefront_id = response.parsed_body.dig("storefront", "storefront_id")
    assert_equal "main-shop", response.parsed_body.dig("storefront", "slug")

    patch api_v1_commerce_storefront_url(storefront_id),
      params: { storefront: { description: "Fresh drops" } },
      headers: tep_headers(owner, "commerce:merchant"),
      as: :json

    assert_response :success
    assert_equal "Fresh drops", response.parsed_body.dig("storefront", "description")
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
