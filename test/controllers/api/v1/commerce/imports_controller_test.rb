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

  test "too many imports get a 429, not a crash" do
    # The import action allows 10 writes a minute. The limiter used to halt
    # the chain by throwing :abort from a block callback, which Rails does not
    # catch — so a catalog import that outran the limit saw a 500 and could
    # not tell throttling from an outage.
    limiter = create_user("import-limiter-#{SecureRandom.hex(4)}")
    headers = tep_headers(limiter, "commerce:merchant")

    11.times do
      post api_v1_commerce_imports_url,
        params: { merchant_id: @merchant.merchant_id, products: [ product_entry ] },
        headers: headers,
        as: :json
    end

    assert_response :too_many_requests
    body = response.parsed_body
    assert_equal "rate_limit_exceeded", body.fetch("error")
    assert_equal 60, body.fetch("retry_after")
  end

  test "a throttled import does not write anything" do
    limiter = create_user("import-throttled-#{SecureRandom.hex(4)}")
    headers = tep_headers(limiter, "commerce:merchant")

    10.times do
      post api_v1_commerce_imports_url,
        params: { merchant_id: @merchant.merchant_id, products: [ product_entry ] },
        headers: headers,
        as: :json
    end

    before = CommerceProduct.where(commerce_merchant: @merchant).count
    post api_v1_commerce_imports_url,
      params: { merchant_id: @merchant.merchant_id, products: [ product_entry ] },
      headers: headers,
      as: :json

    assert_response :too_many_requests
    assert_equal before, CommerceProduct.where(commerce_merchant: @merchant).count
  end

  test "each product carries its own storefront branding" do
    # The scraper imports a marketplace catalog in batches; one batch can span
    # dozens of source stores, and each listing has to land in its own.
    post api_v1_commerce_imports_url,
      params: {
        merchant_id: @merchant.merchant_id,
        products: [
          product_entry.merge(
            storefront: { display_name: "Samsung", slug: "samsung", store_type: "ecommerce" }
          ),
          product_entry.merge(
            source: product_entry.fetch(:source).merge(source_id: "SP-5678"),
            storefront: {
              display_name: "Chimaco Stores",
              slug: "chimaco-stores-konga",
              store_type: "marketplace"
            }
          )
        ]
      },
      headers: tep_headers(@owner, "commerce:merchant"),
      as: :json

    assert_response :success
    slugs = CommerceProduct.where(commerce_merchant: @merchant).map { |p| p.commerce_storefront.slug }
    assert_equal [ "samsung", "chimaco-stores-konga" ].sort, slugs.sort
    assert_equal "Chimaco Stores",
      CommerceProduct.find_by!(source_id: "SP-5678").commerce_storefront.display_name
  end

  # ── Category sync ───────────────────────────────────────────────────

  test "an imported listing lands in Tween's own category tree" do
    # The scraper sends the marketplace's chain of category names. Without a
    # resolution the listing has no category_id, and every category browse on
    # the storefront filters on exactly that — so the listing exists but is
    # invisible.
    suffix = SecureRandom.hex(3)
    entry = product_entry.merge(
      category: {
        path: [ "Test Computers #{suffix}", "Test Laptops #{suffix}" ],
        slugs: [ "computers-#{suffix}", "laptops-#{suffix}" ],
        source_ids: [ "5227", "5230" ]
      }
    )

    post api_v1_commerce_imports_url,
      params: { merchant_id: @merchant.merchant_id, products: [ entry ] },
      headers: tep_headers(@owner, "commerce:merchant"),
      as: :json

    assert_response :success
    product = CommerceProduct.find_by!(source_id: entry.dig(:source, :source_id))

    assert_not_nil product.commerce_category, "listing must be browsable"
    assert_equal "Test Computers #{suffix}".downcase, product.commerce_category.name.downcase
    assert_not_nil product.subcategory_id
    assert_equal "Test Laptops #{suffix}".downcase,
      CommerceCategory.find(product.subcategory_id).name.downcase
    assert_equal [ "Test Computers #{suffix}", "Test Laptops #{suffix}" ],
      product.source_category_path
  end

  test "re-importing a listing keeps one category branch, not a duplicate" do
    suffix = SecureRandom.hex(3)
    entry = product_entry.merge(
      category: { path: [ "Test Phones #{suffix}", "Test Smartphones #{suffix}" ] }
    )
    headers = tep_headers(@owner, "commerce:merchant")

    2.times do
      post api_v1_commerce_imports_url,
        params: { merchant_id: @merchant.merchant_id, products: [ entry ] },
        headers: headers,
        as: :json
      assert_response :success
    end

    assert_equal 1, CommerceCategory.where("lower(name) = ?", "test phones #{suffix}").count
    assert_equal 1, CommerceProduct.find_by!(source_id: entry.dig(:source, :source_id))
      .then { |product| CommerceCategory.where(id: product.subcategory_id) }.count
  end

  test "an explicit category_id still wins over the source chain" do
    category = CommerceCategory.create!(
      name: "Test Chosen #{SecureRandom.hex(3)}", slug: "test-chosen-#{SecureRandom.hex(3)}"
    )
    entry = product_entry.merge(
      category_id: category.category_id,
      category: { path: [ "Test Ignored #{SecureRandom.hex(3)}" ] }
    )

    post api_v1_commerce_imports_url,
      params: { merchant_id: @merchant.merchant_id, products: [ entry ] },
      headers: tep_headers(@owner, "commerce:merchant"),
      as: :json

    assert_response :success
    product = CommerceProduct.find_by!(source_id: entry.dig(:source, :source_id))
    assert_equal category.id, product.category_id
  end

  test "a chain nested inside the product still files the listing" do
    # One version of the scraper sent the chain inside `product` instead of at
    # the top of the entry. Every listing it imported carried its chain and
    # still had no category, because the reader only looked at the top of the
    # entry — so a whole catalog arrived invisible to category browse.
    suffix = SecureRandom.hex(3)
    entry = product_entry.deep_merge(
      source: { source_id: "SP-NEST-#{suffix}" },
      product: { category: { path: [ "Test Nested #{suffix}", "Test Branch #{suffix}" ] } }
    )

    post api_v1_commerce_imports_url,
      params: { merchant_id: @merchant.merchant_id, products: [ entry ] },
      headers: tep_headers(@owner, "commerce:merchant"),
      as: :json

    assert_response :success
    product = CommerceProduct.find_by!(source_id: "SP-NEST-#{suffix}")

    assert_not_nil product.commerce_category, "listing must be browsable"
    assert_equal "Test Nested #{suffix}".downcase, product.commerce_category.name.downcase
    assert_equal [ "Test Nested #{suffix}", "Test Branch #{suffix}" ], product.source_category_path
  end

  test "a listing whose source published no chain is left without a category" do
    suffix = SecureRandom.hex(3)
    entry = product_entry.deep_merge(
      source: { source_id: "SP-NONE-#{suffix}", category_path: nil }
    )

    post api_v1_commerce_imports_url,
      params: { merchant_id: @merchant.merchant_id, products: [ entry ] },
      headers: tep_headers(@owner, "commerce:merchant"),
      as: :json

    assert_response :success
    product = CommerceProduct.find_by!(source_id: "SP-NONE-#{suffix}")

    assert_nil product.category_id
    assert_equal [], product.source_category_path
  end

  # ── Rich source detail ──────────────────────────────────────────────

  test "every field the marketplace published is mirrored onto the listing" do
    entry = product_entry.merge(
      product: product_entry.fetch(:product).merge(
        short_description: "The best phone in the range.",
        condition: "refurbished",
        weight_grams: 500,
        badges: [ "Official Store", "Free Shipping" ],
        specifications: {
          attributes: { "OS" => "iOS", "RAM" => "8 GB" },
          groups: [ { name: "General Features", attributes: { "OS" => "iOS" } } ]
        },
        warranty: { has_warranty: true, period: "1 Year", text: "Apple Warranty" },
        stock: { in_stock: true, quantity: 15, quantity_sold: 1 },
        shipping: { delivery_days: 6, pickup: true, return_policy: { return_days: 7 } },
        identifiers: { sku: "6703587", url_key: "iphone-16-pro-max" },
        variants: { attributes: [ { code: "color" } ] }
      )
    )

    post api_v1_commerce_imports_url,
      params: { merchant_id: @merchant.merchant_id, products: [ entry ] },
      headers: tep_headers(@owner, "commerce:merchant"),
      as: :json

    assert_response :success
    product = CommerceProduct.find_by!(source_id: entry.dig(:source, :source_id))

    assert_equal "The best phone in the range.", product.short_description
    assert_equal "refurbished", product.condition
    assert_equal 500, product.weight_grams
    assert_equal [ "Official Store", "Free Shipping" ], product.badges
    assert_equal "iOS", product.specifications.dig("attributes", "OS")
    assert_equal "General Features", product.specifications.dig("groups", 0, "name")
    assert_equal "1 Year", product.warranty["period"]
    assert_equal 15, product.stock["quantity"]
    assert_equal 6, product.shipping["delivery_days"]
    assert_equal 7, product.shipping.dig("return_policy", "return_days")
    assert_equal "6703587", product.identifiers["sku"]
    assert_equal [ { "code" => "color" } ], product.variants["attributes"]
  end

  test "the source's own attribute vocabulary and shipping regions are mirrored" do
    # The scraper reads these from the marketplace's catalog index, which is
    # the only place they exist for categories whose product page publishes no
    # spec table — so they must survive the import, not just the scrape.
    entry = product_entry.merge(
      product: product_entry.fetch(:product).merge(
        specifications: {
          attributes: { "Ram Gb" => "16 GB" },
          index_attributes: { "brand" => [ "HP" ], "ram_gb" => [ "16 GB" ] }
        },
        shipping: {
          delivery_days: 4,
          availability_locations: %w[Lagos Abuja],
          return_policy: { return_days: 7 }
        },
        identifiers: {
          sku: "7037287",
          seller_id: "118566",
          seller_storefront: "konga-store",
          listed_at: "2026-08-24T09:09:51+00:00"
        }
      )
    )

    post api_v1_commerce_imports_url,
      params: { merchant_id: @merchant.merchant_id, products: [ entry ] },
      headers: tep_headers(@owner, "commerce:merchant"),
      as: :json

    assert_response :success
    product = CommerceProduct.find_by!(source_id: entry.dig(:source, :source_id))

    assert_equal [ "HP" ], product.specifications.dig("index_attributes", "brand")
    assert_equal "16 GB", product.specifications.dig("attributes", "Ram Gb")
    assert_equal %w[Lagos Abuja], product.shipping["availability_locations"]
    assert_equal "konga-store", product.identifiers["seller_storefront"]
    assert_equal "2026-08-24T09:09:51+00:00", product.identifiers["listed_at"]
  end

  test "a payload with the wrong shapes for jsonb columns is stored safely" do
    # A scraper that sends null or a list where an object belongs must not be
    # able to persist something the storefront renders as a broken spec table.
    entry = product_entry.merge(
      product: product_entry.fetch(:product).merge(
        specifications: nil,
        warranty: "warranty text",
        stock: [ 1, 2, 3 ],
        tags: [ "ok", "", nil, "ok" ]
      )
    )

    post api_v1_commerce_imports_url,
      params: { merchant_id: @merchant.merchant_id, products: [ entry ] },
      headers: tep_headers(@owner, "commerce:merchant"),
      as: :json

    assert_response :success
    product = CommerceProduct.find_by!(source_id: entry.dig(:source, :source_id))

    assert_equal({}, product.specifications)
    assert_equal({}, product.warranty)
    assert_equal({}, product.stock)
    assert_equal [ "ok" ], product.tags
  end

  test "a variant image is mirrored onto the sku" do
    entry = product_entry.merge(
      skus: [
        product_entry.fetch(:skus).first.merge(
          source_sku_id: "SP-1234-BLK",
          image: "https://cdn.tween.im/commerce/konga/1.jpg",
          quantity_available: 4
        )
      ]
    )

    post api_v1_commerce_imports_url,
      params: { merchant_id: @merchant.merchant_id, products: [ entry ] },
      headers: tep_headers(@owner, "commerce:merchant"),
      as: :json

    assert_response :success
    product = CommerceProduct.find_by!(source_id: entry.dig(:source, :source_id))
    sku = product.commerce_skus.find_by!(title: "Black")

    assert_equal "https://cdn.tween.im/commerce/konga/1.jpg", sku.image_url
    assert_equal 4, sku.quantity_available
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
