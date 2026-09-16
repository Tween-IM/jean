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

  # ── Catalog paging ──────────────────────────────────────────────────
  # The mobile app pages the catalog with `next_cursor`; before this the
  # endpoint returned neither a cursor nor an offset, so the app never had a
  # second page to ask for and the grid dead-ended after twenty products.

  test "index walks the whole catalog with a cursor, without gaps or repeats" do
    owner = create_user("paging-owner")
    merchant = merchant_for(owner)
    expected = 5.times.map { |i| listing(merchant, "Cursor Item #{i}", 1_000 * (i + 1)).title }

    walked = []
    cursor = nil
    3.times do
      body = get_product_page(owner, limit: 2, sort: "price_asc", cursor: cursor)
      walked.concat(body["products"].map { |product| product["title"] })
      cursor = body["next_cursor"]
      refute_nil cursor if walked.length < expected.length
    end

    assert_equal expected, walked
    assert_nil cursor, "the last page must not offer another cursor"
  end

  test "index reports the full match count, not just the page" do
    owner = create_user("paging-count-owner")
    merchant = merchant_for(owner)
    3.times { |i| listing(merchant, "Counted #{i}", 1_000 * (i + 1)) }

    body = get_product_page(owner, limit: 2)

    assert_equal 2, body["products"].length
    assert_equal 3, body.dig("meta", "total")
  end

  test "index ignores a cursor it cannot read instead of failing" do
    owner = create_user("paging-bad-cursor-owner")
    merchant = merchant_for(owner)
    listing(merchant, "Still Reachable", 2_000)

    get "/api/v1/commerce/products",
      params: { limit: 20, cursor: "not-a-real-cursor" },
      headers: tep_headers(owner, "commerce:read")

    assert_response :success
    assert_equal [ "Still Reachable" ], response.parsed_body["products"].map { |p| p["title"] }
  end

  # ── Price reads the cheapest SKU ────────────────────────────────────

  test "price filters and sorting use the listing's cheapest SKU" do
    owner = create_user("sku-price-owner")
    merchant = merchant_for(owner)
    # A join would match the 900k SKU and drag the listing into the filter; the
    # listing is really a 1k one and must stay out of a 50k+ range.
    spread = listing(merchant, "Wide Spread", 1_000, extra_price: 900_000)
    single = listing(merchant, "Mid Priced", 500_000)

    body = get_product_page(owner, min_price: 50_000)
    assert_equal [ single.product_id ], body["products"].map { |p| p["product_id"] }
    refute_includes body["products"].map { |p| p["product_id"] }, spread.product_id

    ascending = get_product_page(owner, sort: "price_asc")
    assert_equal [ spread.product_id, single.product_id ], ascending["products"].map { |p| p["product_id"] }

    descending = get_product_page(owner, sort: "price_desc")
    assert_equal [ single.product_id, spread.product_id ], descending["products"].map { |p| p["product_id"] }
  end

  # ── Sort orders that are computed expressions ───────────────────────

  test "popular and rating sorts order without a DISTINCT violation" do
    owner = create_user("computed-sort-owner")
    merchant = merchant_for(owner)
    quiet = listing(merchant, "Quiet", 1_000, sales_count: 1, rating_average: 2.0)
    busy = listing(merchant, "Busy", 1_000, sales_count: 50, rating_average: 4.9)

    assert_equal [ busy.product_id, quiet.product_id ],
      get_product_page(owner, sort: "popular")["products"].map { |p| p["product_id"] }
    assert_equal [ busy.product_id, quiet.product_id ],
      get_product_page(owner, sort: "rating")["products"].map { |p| p["product_id"] }
    assert_equal [ busy.product_id, quiet.product_id ],
      get_product_page(owner, sort: "newest")["products"].map { |p| p["product_id"] }
  end

  test "popular sort pages with a cursor" do
    owner = create_user("popular-cursor-owner")
    merchant = merchant_for(owner)
    ranked = 4.times.map { |i| listing(merchant, "Ranked #{i}", 1_000, sales_count: i * 10) }
    expected = ranked.reverse.map(&:product_id)

    walked = []
    cursor = nil
    2.times do
      body = get_product_page(owner, limit: 2, sort: "popular", cursor: cursor)
      walked.concat(body["products"].map { |p| p["product_id"] })
      cursor = body["next_cursor"]
    end

    assert_equal expected, walked
    assert_nil cursor
  end

  # ── Category browsing ───────────────────────────────────────────────

  test "browsing a top level category reaches products filed under its children" do
    owner = create_user("parent-category-owner")
    merchant = merchant_for(owner)
    parent = CommerceCategory.create!(name: "Phones & Tablets", slug: "phones-tablets-browse", status: "active")
    child = CommerceCategory.create!(name: "Smartphones", slug: "smartphones-browse", status: "active", parent_id: parent.id)
    grandchild = CommerceCategory.create!(name: "Android Phones", slug: "android-phones-browse", status: "active", parent_id: child.id)

    # The importer files a listing under the top of its chain as `category_id`
    # and its leaf as `subcategory_id`, so both storage shapes must be reached.
    # A branch is matched on either column, which is why the top-filed listing
    # answers for the parent and the leaf-filed one answers for both its parent
    # and its own leaf.
    top_filed = listing(merchant, "Top Filed", 1_000, category: parent)
    leaf_filed = merchant.commerce_products.create!(
      title: "Leaf Filed", status: "active", condition: "new", category_id: parent.id, subcategory_id: grandchild.id
    )
    leaf_filed.commerce_skus.create!(title: "Default", price_cents: 2_000, currency: "NGN", inventory_status: "in_stock")

    body = get_product_page(owner, category_id: parent.category_id, limit: 50)
    titles = body["products"].map { |p| p["title"] }
    assert_includes titles, top_filed.title
    assert_includes titles, leaf_filed.title

    assert_equal [ leaf_filed.product_id ],
      get_product_page(owner, category_id: child.category_id, limit: 50)["products"].map { |p| p["product_id"] }

    assert_equal [ leaf_filed.product_id ],
      get_product_page(owner, category_id: grandchild.category_id, limit: 50)["products"].map { |p| p["product_id"] }
  end

  test "index filters by condition, which the browse surfaces expose" do
    owner = create_user("condition-filter-owner")
    merchant = merchant_for(owner)
    fresh = listing(merchant, "Fresh", 1_000)
    worn = merchant.commerce_products.create!(title: "Worn", status: "active", condition: "used")
    worn.commerce_skus.create!(title: "Default", price_cents: 3_000, currency: "NGN", inventory_status: "in_stock")

    assert_equal [ fresh.product_id ],
      get_product_page(owner, condition: "new")["products"].map { |p| p["product_id"] }
    assert_equal [ worn.product_id ],
      get_product_page(owner, condition: "used")["products"].map { |p| p["product_id"] }
  end

  test "browsing an unknown category returns an empty page, not the whole catalog" do
    owner = create_user("empty-category-owner")
    merchant = merchant_for(owner)
    listing(merchant, "Unrelated", 1_000)

    body = get_product_page(owner, category_id: "categ_does_not_exist")

    assert_empty body["products"]
    assert_equal 0, body.dig("meta", "total")
    assert_nil body["next_cursor"]
  end

  private

  def merchant_for(user)
    CommerceMerchant.create!(owner_user_id: user.matrix_user_id, miniapp_id: "miniapp.shop.test", display_name: "Shop", status: "active")
  end

  def listing(merchant, title, price_cents, extra_price: nil, sales_count: 0, rating_average: 0.0, category: nil)
    product = merchant.commerce_products.create!(
      title: title, status: "active", condition: "new",
      sales_count: sales_count, rating_average: rating_average, category_id: category&.id
    )
    product.commerce_skus.create!(title: "Default", price_cents: price_cents, currency: "NGN", inventory_status: "in_stock")
    if extra_price
      product.commerce_skus.create!(title: "Premium", price_cents: extra_price, currency: "NGN", inventory_status: "in_stock")
    end
    product
  end

  # Two landmines here. `api_v1_commerce_products_url` resolves to the POST
  # create route (`resources` puts index and create on one path), and in Rails
  # 8.1 a GET carrying both `params:` and `as: :json` is dispatched as a POST —
  # which lands on create and answers 403 for a read-only token. So the read
  # helper sends params without a JSON body.
  def get_product_page(user, params = {})
    get "/api/v1/commerce/products",
      params: params.compact,
      headers: tep_headers(user, "commerce:read")
    assert_response :success
    response.parsed_body
  end

  def create_user(username)
    User.create!(matrix_user_id: "@#{username}:example.com", matrix_username: "#{username}:example.com", matrix_homeserver: "example.com")
  end

  def tep_headers(user, scopes)
    token = TepTokenService.encode({ user_id: user.matrix_user_id, miniapp_id: "miniapp.shop.test" }, scopes: scopes.split)
    { "Authorization" => "Bearer #{token}" }
  end
end
