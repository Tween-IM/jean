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

  test "show reports review eligibility only after a purchase" do
    owner = create_user("review-elig-owner")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "miniapp.shop.test", display_name: "Shop", status: "active")
    product = merchant.commerce_products.create!(title: "Camry 2018", status: "active", condition: "used")

    # Buyer with no purchase — not eligible.
    buyer = create_user("review-elig-buyer")
    get api_v1_commerce_product_url(product.product_id),
        headers: tep_headers(buyer, "commerce:read"),
        as: :json
    assert_response :success
    assert_equal false, response.parsed_body.dig("review_eligibility", "eligible")

    # After a paid order — eligible.
    merchant.commerce_orders.create!(
      buyer_user_id: buyer.matrix_user_id,
      payment_id: "pay_review_elig",
      status: "paid",
      subtotal_cents: 1000, total_cents: 1000, currency: "NGN"
    )
    get api_v1_commerce_product_url(product.product_id),
        headers: tep_headers(buyer, "commerce:read"),
        as: :json
    assert_response :success
    assert_equal true, response.parsed_body.dig("review_eligibility", "eligible")
  end

  test "search filters by price range and condition" do
    owner = create_user("search-filter-owner")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "miniapp.shop.test", display_name: "Shop", status: "active")
    category = CommerceCategory.create!(name: "Phones", slug: "phones", status: "active")

    cheap_new = merchant.commerce_products.create!(title: "Cheap New", status: "active", condition: "new", category_id: category.id)
    cheap_new.commerce_skus.create!(title: "Default", price_cents: 5_000, currency: "NGN", inventory_status: "in_stock")
    pricey_used = merchant.commerce_products.create!(title: "Pricey Used", status: "active", condition: "used", category_id: category.id)
    pricey_used.commerce_skus.create!(title: "Default", price_cents: 80_000, currency: "NGN", inventory_status: "in_stock")

    get "/api/v1/commerce/products/search?category_id=#{category.category_id}&min_price=1000&max_price=50000&condition=new",
        headers: tep_headers(owner, "commerce:read"),
        as: :json

    assert_response :success
    titles = response.parsed_body["products"].map { |p| p["title"] }
    assert_includes titles, "Cheap New"
    refute_includes titles, "Pricey Used"
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
