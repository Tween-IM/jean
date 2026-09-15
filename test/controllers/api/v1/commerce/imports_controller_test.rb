# frozen_string_literal: true

require "test_helper"

class Api::V1::Commerce::ImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Unique usernames per test: the rate limiter counts in Redis, which is not
    # rolled back between transactional tests.
    suffix = SecureRandom.hex(4)
    @owner = create_user("import-owner-#{suffix}")
    @stranger = create_user("import-stranger-#{suffix}")
    @merchant = CommerceMerchant.create!(
      owner_user_id: @owner.matrix_user_id,
      miniapp_id: "miniapp.shop.test",
      display_name: "Jumia Deals",
      status: "active"
    )
  end

  test "imports a product with provenance, skus and storefront branding" do
    post api_v1_commerce_imports_url,
      params: {
        merchant_id: @merchant.merchant_id,
        storefront: { display_name: "Jumia Deals", banner_url: "https://cdn.example/banner.jpg" },
        products: [ product_entry ]
      },
      headers: tep_headers(@owner, "commerce:merchant"),
      as: :json

    assert_response :success
    result = response.parsed_body.fetch("results").first
    assert_equal "created", result.fetch("action")
    assert_equal "jumia", result.fetch("source_platform")
    assert_equal "SP-1234", result.fetch("source_id")
    assert_equal 1, result.fetch("skus")
    assert_equal 2, result.fetch("reviews")

    product = CommerceProduct.find_by!(product_id: result.fetch("product_id"))
    assert_equal "jumia", product.source_platform
    assert_equal "SP-1234", product.source_id
    assert_equal "https://www.jumia.com.ng/product", product.source_url
    assert_equal "Phones & Tablets", product.source_payload.dig("category_path", 0)
    assert_not_nil product.source_synced_at
    assert_equal "active", product.status
    assert_equal "ecommerce", product.store_type
    assert_equal "Jumia Deals", product.commerce_storefront.display_name
    assert_equal "https://cdn.example/banner.jpg", product.commerce_storefront.banner_url
    assert_equal [ "Nigeria", "Lagos" ], product.tags
    assert_includes product.media_urls, "https://cdn.tween.im/jumia/1-large.jpg"

    sku = product.commerce_skus.first
    assert_equal "SP-1234-BLK", sku.properties.fetch("source_sku_id")
    assert_equal 250_000, sku.price_cents
    assert_equal "NGN", sku.currency
  end

  test "re-importing the same source record updates instead of duplicating" do
    2.times do
      post api_v1_commerce_imports_url,
        params: { merchant_id: @merchant.merchant_id, products: [ product_entry ] },
        headers: tep_headers(@owner, "commerce:merchant"),
        as: :json
      assert_response :success
    end

    actions = CommerceProduct.imported.count
    assert_equal 1, actions
    assert_equal 1, CommerceSku.where("properties->>'source_sku_id' = ?", "SP-1234-BLK").count
    assert_equal 2, CommerceReview.where(source_platform: "jumia").count
  end

  test "re-import marks skus missing from the new payload out of stock" do
    post api_v1_commerce_imports_url,
      params: { merchant_id: @merchant.merchant_id, products: [ product_entry ] },
      headers: tep_headers(@owner, "commerce:merchant"),
      as: :json
    product_id = response.parsed_body.dig("results", 0, "product_id")

    entry = product_entry
    entry[:skus] = [ entry[:skus].first.except(:source_sku_id) ]
    entry[:skus][0][:title] = "Jumia SP-1234 (Renewed)"

    post api_v1_commerce_imports_url,
      params: { merchant_id: @merchant.merchant_id, products: [ entry ] },
      headers: tep_headers(@owner, "commerce:merchant"),
      as: :json

    assert_response :success
    assert_equal "updated", response.parsed_body.dig("results", 0, "action")

    product = CommerceProduct.find_by!(product_id: product_id)
    assert_equal 2, product.commerce_skus.count, "existing skus are kept, not destroyed"
    assert_equal 1, product.commerce_skus.where(inventory_status: "out_of_stock").count
  end

  test "imported reviews expose canonical or anonymous reviewer identity" do
    post api_v1_commerce_imports_url,
      params: { merchant_id: @merchant.merchant_id, products: [ product_entry ] },
      headers: tep_headers(@owner, "commerce:merchant"),
      as: :json
    product_id = response.parsed_body.dig("results", 0, "product_id")

    named = CommerceReview.find_by!(source_review_id: "R-1")
    assert_equal "Chidinma O.", named.reviewer_display_name
    assert_equal "chidinma-o", named.reviewer_handle
    assert_not named.is_anonymous
    assert named.imported
    assert_equal "approved", named.status
    assert_equal "import:jumia:R-1", named.buyer_user_id

    anonymous = CommerceReview.find_by!(source_review_id: "R-2")
    assert anonymous.is_anonymous
    assert_equal "Anonymous Buyer", anonymous.reviewer_display_name
    assert_equal "Anonymous", anonymous.reviewer_handle
  end

  test "product show surfaces the imported reviewer identity" do
    post api_v1_commerce_imports_url,
      params: { merchant_id: @merchant.merchant_id, products: [ product_entry ] },
      headers: tep_headers(@owner, "commerce:merchant"),
      as: :json
    product_id = response.parsed_body.dig("results", 0, "product_id")

    get api_v1_commerce_product_url(product_id),
      headers: tep_headers(@owner, "commerce:read"),
      as: :json

    assert_response :success
    reviews = response.parsed_body.fetch("reviews")
    assert_equal 2, reviews.size

    named = reviews.find { |r| r.fetch("review_id") == CommerceReview.find_by!(source_review_id: "R-1").review_id }
    assert_equal "Chidinma O.", named.fetch("reviewer_display_name")
    assert_equal true, named.fetch("imported")
    assert_equal "jumia", named.fetch("source_platform")

    anonymous = reviews.find { |r| r.fetch("is_anonymous") }
    assert_equal "Anonymous Buyer", anonymous.fetch("reviewer_display_name")
  end

  test "buyers cannot import into a merchant they do not own" do
    post api_v1_commerce_imports_url,
      params: { merchant_id: @merchant.merchant_id, products: [ product_entry ] },
      headers: tep_headers(@stranger, "commerce:merchant"),
      as: :json

    assert_response :forbidden
    assert_equal 0, CommerceProduct.imported.count
  end

  test "import requires a source identity" do
    entry = product_entry
    entry[:source] = { platform: "jumia" }

    post api_v1_commerce_imports_url,
      params: { merchant_id: @merchant.merchant_id, products: [ entry ] },
      headers: tep_headers(@owner, "commerce:merchant"),
      as: :json

    assert_response :success
    result = response.parsed_body.fetch("results").first
    assert_equal "failed", result.fetch("action")
    assert_match(/source_id is required/, result.fetch("error"))
  end

  test "lookup reconciles source identities to storefront ids" do
    post api_v1_commerce_imports_url,
      params: { merchant_id: @merchant.merchant_id, products: [ product_entry ] },
      headers: tep_headers(@owner, "commerce:merchant"),
      as: :json
    product_id = response.parsed_body.dig("results", 0, "product_id")

    post lookup_api_v1_commerce_imports_url,
      params: {
        merchant_id: @merchant.merchant_id,
        items: [ { source_platform: "jumia", source_id: "SP-1234" }, { source_platform: "konga", source_id: "NOPE" } ]
      },
      headers: tep_headers(@owner, "commerce:read"),
      as: :json

    assert_response :success
    products = response.parsed_body.fetch("products")
    assert_equal 1, products.size
    assert_equal product_id, products.first.fetch("product_id")
  end

  test "each source platform gets its own branded storefront" do
    jumia_entry = product_entry
    konga_entry = product_entry.tap { |e| e[:source] = e[:source].merge(platform: "konga", source_id: "KG-9") }

    import_entry(jumia_entry, storefront: {
      display_name: "Jumia on Tween",
      slug: "jumia-on-tween",
      banner_url: "https://cdn.example/jumia-banner.jpg"
    })
    import_entry(konga_entry, storefront: {
      display_name: "Konga on Tween",
      slug: "konga-on-tween"
    })

    storefronts = @merchant.commerce_storefronts.reload.index_by(&:slug)
    assert_equal %w[jumia-on-tween konga-on-tween], storefronts.keys.sort
    assert_equal "Jumia on Tween", storefronts["jumia-on-tween"].display_name
    assert_equal "https://cdn.example/jumia-banner.jpg", storefronts["jumia-on-tween"].banner_url
    assert_equal "Konga on Tween", storefronts["konga-on-tween"].display_name

    jumia_product = CommerceProduct.find_by!(source_platform: "jumia", source_id: "SP-1234")
    konga_product = CommerceProduct.find_by!(source_platform: "konga", source_id: "KG-9")
    assert_equal storefronts["jumia-on-tween"].id, jumia_product.commerce_storefront_id
    assert_equal storefronts["konga-on-tween"].id, konga_product.commerce_storefront_id
  end

  test "an explicit storefront_id pins the import to that store" do
    jumia_entry = product_entry
    import_entry(jumia_entry, storefront: { display_name: "Jumia on Tween", slug: "jumia-on-tween" })
    storefront = @merchant.commerce_storefronts.find_by!(slug: "jumia-on-tween")

    pinned = product_entry.tap { |e| e[:source] = e[:source].merge(source_id: "SP-PINNED") }
    import_entry(pinned, storefront: { display_name: "Pinned Store", slug: "pinned-store" }, storefront_id: storefront.storefront_id)

    product = CommerceProduct.find_by!(source_platform: "jumia", source_id: "SP-PINNED")
    assert_equal storefront.id, product.commerce_storefront_id
    assert_equal 1, @merchant.commerce_storefronts.count, "an explicit storefront_id must not create another store"
  end

  test "imports a storefront with branding, provenance and contact details" do
    entry = product_entry
    entry[:storefront] = seller_storefront

    result = import_entry(entry)
    storefront = CommerceProduct.find_by!(product_id: result.fetch("product_id")).commerce_storefront

    assert_equal "Bella's Coutures", storefront.display_name
    assert_equal "bella-s-coutures-jumia", storefront.slug
    assert_equal "marketplace", storefront.store_type
    assert_equal "published", storefront.status
    assert_equal "Ankara and ready-to-wear, made in Lagos.", storefront.about
    assert_equal "https://cdn.tween.im/stores/jumia/bella-s-coutures/logo.jpg", storefront.logo_url
    assert_equal "https://cdn.tween.im/stores/jumia/bella-s-coutures/banner.jpg", storefront.banner_url

    assert_equal "jumia", storefront.source_platform
    assert_equal "seller", storefront.source_kind
    assert_equal "best-class-stores", storefront.source_id
    assert_equal "https://www.jumia.com.ng/best-class-stores/", storefront.source_url
    assert_not_nil storefront.source_synced_at
    assert_equal "seller", storefront.source_payload.fetch("kind")

    assert_equal "+2348012345678", storefront.contact_phone
    assert_equal "hello@bellas.example", storefront.contact_email
    assert_equal "https://bellas.example", storefront.contact_website
    assert_equal "12 Adeniran Ogunsanya, Surulere, Lagos", storefront.contact_address
    assert_equal({ "instagram" => "https://instagram.com/bellas" }, storefront.social_links)
  end

  test "storefront contact details are private to the merchant owner" do
    entry = product_entry
    entry[:storefront] = seller_storefront
    result = import_entry(entry)
    storefront = CommerceProduct.find_by!(product_id: result.fetch("product_id")).commerce_storefront

    get api_v1_commerce_storefront_url(storefront.storefront_id),
      headers: tep_headers(@owner, "commerce:read"),
      as: :json

    assert_response :success
    owner_view = response.parsed_body.fetch("storefront")
    assert_equal "+2348012345678", owner_view.dig("contact", "phone")
    assert_equal "hello@bellas.example", owner_view.dig("contact", "email")
    assert_equal "jumia", owner_view.fetch("source_platform")
    assert_equal true, owner_view.fetch("imported")

    get api_v1_commerce_storefront_url(storefront.storefront_id),
      headers: tep_headers(@stranger, "commerce:read"),
      as: :json

    assert_response :success
    public_view = response.parsed_body.fetch("storefront")
    assert_nil public_view["contact"], "contact details must never be public"
    assert_nil public_view["source_payload"], "raw source payload must never be public"
    assert_equal "jumia", public_view.fetch("source_platform"), "provenance stays visible"
    assert_equal "https://www.jumia.com.ng/best-class-stores/", public_view.fetch("source_url")
  end

  test "an imported store's bio is public while its contact details are not" do
    entry = product_entry
    entry[:storefront] = seller_storefront
    result = import_entry(entry)
    storefront = CommerceProduct.find_by!(product_id: result.fetch("product_id")).commerce_storefront

    get api_v1_commerce_storefront_url(storefront.storefront_id),
      headers: tep_headers(@stranger, "commerce:read"),
      as: :json

    assert_response :success
    public_view = response.parsed_body.fetch("storefront")
    assert_equal storefront.about, public_view.fetch("about"),
      "the storefront page renders about, so it must be public"
    assert_nil public_view["contact"]
    assert_nil public_view["source_payload"]
  end

  test "brand storefronts carry their source url and description" do
    entry = product_entry
    entry[:source] = entry[:source].merge(source_id: "SP-BRAND", brand: "Samsung")
    entry[:storefront] = {
      display_name: "Samsung",
      slug: "samsung",
      store_type: "ecommerce",
      about: "Discover Samsung phones, TVs, tablets and home appliances.",
      source: {
        platform: "jumia",
        kind: "brand",
        source_id: "samsung",
        source_url: "https://www.jumia.com.ng/samsung/"
      }
    }

    result = import_entry(entry)
    storefront = CommerceProduct.find_by!(product_id: result.fetch("product_id")).commerce_storefront

    assert_equal "samsung", storefront.slug
    assert_equal "brand", storefront.source_kind
    assert_equal "https://www.jumia.com.ng/samsung/", storefront.source_url
    assert_match(/phones, TVs, tablets/, storefront.about)
    assert_nil storefront.contact_phone, "brands publish no contact details"
  end

  test "an unknown source kind is ignored rather than failing the import" do
    entry = product_entry
    entry[:storefront] = {
      display_name: "Mystery Store",
      slug: "mystery-store",
      source: { platform: "jumia", kind: "not-a-kind", source_id: "mystery" }
    }

    result = import_entry(entry)
    storefront = CommerceProduct.find_by!(product_id: result.fetch("product_id")).commerce_storefront

    assert_equal "Mystery Store", storefront.display_name
    assert_nil storefront.source_kind
    assert_equal "jumia", storefront.source_platform
  end

  test "a crawl with no merchant of its own writes to the platform merchant" do
    post api_v1_commerce_imports_url,
      params: { products: [ product_entry ] },
      headers: tep_headers(@owner, "commerce:merchant"),
      as: :json

    assert_response :success
    product = CommerceProduct.find_by!(product_id: response.parsed_body.dig("results", 0, "product_id"))

    assert product.commerce_merchant.system_owned?
    assert_equal CommerceMerchant::SYSTEM_MERCHANT_ID, product.commerce_merchant.merchant_id
  end

  test "the import scope may write to the platform merchant without owning it" do
    system_merchant = CommerceMerchant.system_merchant

    post api_v1_commerce_imports_url,
      params: { merchant_id: system_merchant.merchant_id, products: [ product_entry ] },
      headers: tep_headers(@stranger, "commerce:merchant"),
      as: :json

    assert_response :success
  end

  private

  def seller_storefront
    {
      display_name: "Bella's Coutures",
      slug: "bella-s-coutures-jumia",
      store_type: "marketplace",
      about: "Ankara and ready-to-wear, made in Lagos.",
      description: "Ankara and ready-to-wear.",
      logo_url: "https://cdn.tween.im/stores/jumia/bella-s-coutures/logo.jpg",
      banner_url: "https://cdn.tween.im/stores/jumia/bella-s-coutures/banner.jpg",
      source: {
        platform: "jumia",
        kind: "seller",
        source_id: "best-class-stores",
        source_url: "https://www.jumia.com.ng/best-class-stores/",
        scraped_at: Time.current.iso8601
      },
      contact: {
        phone: "+2348012345678",
        email: "hello@bellas.example",
        website: "https://bellas.example",
        address: "12 Adeniran Ogunsanya, Surulere, Lagos",
        social_links: { instagram: "https://instagram.com/bellas" }
      }
    }
  end

  def import_entry(entry, storefront: nil, storefront_id: nil)
    params = { merchant_id: @merchant.merchant_id, products: [ entry ] }
    params[:storefront] = storefront if storefront
    params[:storefront_id] = storefront_id if storefront_id

    post api_v1_commerce_imports_url,
      params: params,
      headers: tep_headers(@owner, "commerce:merchant"),
      as: :json

    assert_response :success
    response.parsed_body.fetch("results").first
  end

  def product_entry
    {
      source: {
        platform: "jumia",
        source_id: "SP-1234",
        source_url: "https://www.jumia.com.ng/product",
        brand: "Samsung",
        category_path: [ "Phones & Tablets", "Mobile Phones" ],
        seller_name: "Jumia Express",
        rating_average: 4.6,
        rating_count: 128,
        scraped_at: Time.current.iso8601
      },
      product: {
        title: "Samsung Galaxy A55 128GB",
        description: "A great phone.",
        media_urls: [ "https://cdn.tween.im/jumia/1-large.jpg" ],
        tags: [ "Nigeria", "Lagos" ],
        condition: "new",
        status: "active",
        dimensions: { brand: "Samsung", source_url: "https://www.jumia.com.ng/product" },
        seo_title: "Samsung Galaxy A55",
        seo_description: "Buy the Samsung Galaxy A55 at the best price."
      },
      skus: [
        {
          source_sku_id: "SP-1234-BLK",
          title: "Black",
          price_cents: 250_000,
          currency: "NGN",
          inventory_status: "in_stock",
          quantity_available: 10,
          properties: { color: "black" }
        }
      ],
      reviews: [
        {
          source_review_id: "R-1",
          reviewer_display_name: "Chidinma O.",
          reviewer_handle: "chidinma-o",
          is_anonymous: false,
          rating: 5,
          title: "Excellent",
          body: "Works perfectly.",
          helpful_count: 3,
          verified_purchase: true,
          review_date: "2026-08-01T10:00:00Z"
        },
        {
          source_review_id: "R-2",
          is_anonymous: true,
          rating: 4,
          title: nil,
          body: "Good value.",
          helpful_count: 0
        }
      ]
    }
  end

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
