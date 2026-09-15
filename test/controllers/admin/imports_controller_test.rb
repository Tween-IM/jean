# frozen_string_literal: true

require "test_helper"

# The admin import screens are the operator view of what the scraper mirrored
# into Tween. These tests pin down three things: who may look, who may change,
# and that a change only ever touches imported rows.
class Admin::ImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    suffix = SecureRandom.hex(4)

    @owner = create_user("import-owner-#{suffix}")
    @merchant = CommerceMerchant.create!(
      owner_user_id: @owner.matrix_user_id,
      miniapp_id: "miniapp.shop.test",
      display_name: "Jumia Deals",
      status: "active"
    )

    @storefront = @merchant.commerce_storefronts.create!(
      display_name: "Bella's Coutures",
      slug: "bellas-coutures-jumia",
      status: "published",
      store_type: "marketplace",
      source_platform: "jumia",
      source_kind: "seller",
      source_id: "bellas-coutures",
      source_url: "https://www.jumia.com.ng/bellas-coutures/",
      source_synced_at: 1.hour.ago,
      source_payload: { "kind" => "seller", "platform" => "jumia", "source_id" => "bellas-coutures" }
    )

    @product = @merchant.commerce_products.create!(
      title: "Ankara Print Dress",
      commerce_storefront: @storefront,
      status: "active",
      source_platform: "jumia",
      source_id: "SP-1",
      source_url: "https://www.jumia.com.ng/ankara-print-dress.html",
      source_synced_at: 1.hour.ago,
      source_payload: { "brand" => "Bella", "seller_name" => "Bella's Coutures" }
    )
    @sku = @product.commerce_skus.create!(
      title: "Medium",
      price_cents: 1_250_000,
      currency: "NGN",
      quantity_available: 3,
      properties: { "source_sku_id" => "SP-1-M" }
    )

    @review = CommerceReview.create!(
      commerce_product: @product,
      commerce_merchant: @merchant,
      buyer_user_id: "import:jumia:R-1",
      rating: 5,
      status: "approved",
      imported: true,
      reviewer_display_name: "Chidinma O.",
      source_platform: "jumia",
      source_review_id: "R-1"
    )

    # Rows that did *not* come from a marketplace: the admin surface must
    # ignore them entirely, not just hide them.
    @plain_storefront = @merchant.commerce_storefronts.create!(
      display_name: "Plain Store", slug: "plain-store", status: "published"
    )
    @plain_product = @merchant.commerce_products.create!(title: "Plain Product", status: "active")
    @plain_review = CommerceReview.create!(
      commerce_product: @plain_product, commerce_merchant: @merchant, buyer_user_id: "buyer-1", rating: 4
    )

    @super_admin = create_admin("super-#{suffix}", :super_admin)
    @ops_manager = create_admin("ops-manager-#{suffix}", :operations_manager)
    @support = create_admin("support-#{suffix}", :support)
    @analyst = create_admin("analyst-#{suffix}", :operations_analyst)
    @compliance = create_admin("compliance-#{suffix}", :compliance_officer)
  end

  # ── Who may look ─────────────────────────────────────────────────────

  test "anonymous visitors are sent to the admin login" do
    get admin_imports_path
    assert_redirected_to admin_login_path
  end

  test "platform admins without the imports permission are turned away" do
    sign_in_as(@compliance)

    get admin_imports_path
    assert_redirected_to admin_dashboard_path
  end

  test "support and analysts can monitor imported stores and listings" do
    [ @support, @analyst ].each do |admin|
      sign_in_as(admin)

      get admin_imports_path
      assert_response :success
      assert_match "External catalog imports", response.body

      get admin_import_storefronts_path
      assert_response :success
      assert_match "Coutures", response.body

      get admin_import_products_path
      assert_response :success
      assert_match "Ankara Print Dress", response.body
    end
  end

  test "the overview reports what was imported and what still needs contact" do
    sign_in_as(@ops_manager)

    get admin_imports_path
    assert_response :success
    assert_match "External catalog imports", response.body
    assert_match "Outreach needed", response.body
  end

  test "the store detail page renders branding, provenance and imported reviews" do
    sign_in_as(@ops_manager)

    get admin_import_storefront_path(@storefront)
    assert_response :success
    assert_match "Store settings", response.body
    assert_match "Provenance", response.body
    assert_match "https://www.jumia.com.ng/bellas-coutures/", response.body
    assert_match "Chidinma O.", response.body
  end

  test "the listing detail page renders variants, reviews and provenance" do
    sign_in_as(@ops_manager)

    get admin_import_product_path(@product)
    assert_response :success
    assert_match "Listing settings", response.body
    assert_match "Variants (SKUs)", response.body
    assert_match "SP-1-M", response.body
    assert_match "Chidinma O.", response.body
    assert_match "Bella&#39;s Coutures", response.body
  end

  test "an invalid storefront change re-renders the form instead of saving" do
    sign_in_as(@ops_manager)

    patch admin_import_storefront_path(@storefront),
      params: { commerce_storefront: { accent_color: "not-a-colour" } }

    assert_response :unprocessable_entity
    assert_match "Store settings", response.body
    assert_equal "#7C3AED", @storefront.reload.accent_color
  end

  test "an invalid listing change re-renders the form instead of saving" do
    sign_in_as(@ops_manager)

    patch admin_import_product_path(@product), params: { commerce_product: { status: "banana" } }

    assert_response :unprocessable_entity
    assert_match "Listing settings", response.body
    assert_equal "active", @product.reload.status
  end

  test "the dashboard surfaces the imported catalog" do
    sign_in_as(@super_admin)

    get admin_dashboard_path
    assert_response :success
    assert_match "Imported catalog", response.body
    assert_match "Awaiting contact", response.body
  end

  # ── Who may change ───────────────────────────────────────────────────

  test "support cannot change an imported store" do
    sign_in_as(@support)

    patch admin_import_storefront_path(@storefront),
      params: { commerce_storefront: { display_name: "Hijacked" } }

    assert_redirected_to admin_dashboard_path
    assert_equal "Bella's Coutures", @storefront.reload.display_name
  end

  test "an operations manager can record branding and contact details" do
    sign_in_as(@ops_manager)

    patch admin_import_storefront_path(@storefront), params: {
      commerce_storefront: {
        display_name: "Bella Couture",
        store_type: "ecommerce",
        status: "published",
        accent_color: "#123456",
        featured: "1",
        about: "Lagos-made occasion wear.",
        contact_phone: "+234 801 000 0000",
        contact_email: "hello@bella.example",
        contact_website: "https://bella.example",
        contact_address: "12 Marina, Lagos"
      }
    }

    assert_redirected_to admin_import_storefront_path(@storefront)
    @storefront.reload
    assert_equal "Bella Couture", @storefront.display_name
    assert_equal "ecommerce", @storefront.store_type
    assert_equal "#123456", @storefront.accent_color
    assert @storefront.featured
    assert_equal "Lagos-made occasion wear.", @storefront.about
    assert_equal "+234 801 000 0000", @storefront.contact_phone
    assert_equal "hello@bella.example", @storefront.contact_email
    assert_equal "https://bella.example", @storefront.contact_website
    assert_equal "12 Marina, Lagos", @storefront.contact_address
    assert_not CommerceStorefront.imported.without_contact.exists?(@storefront.id)
  end

  test "an operations manager can take an imported listing off the storefront" do
    sign_in_as(@ops_manager)

    patch admin_import_product_path(@product),
      params: { commerce_product: { status: "archived", featured: "1" } }

    assert_redirected_to admin_import_product_path(@product)
    @product.reload
    assert_equal "archived", @product.status
    assert @product.featured
  end

  test "an operations manager can moderate an imported review" do
    sign_in_as(@ops_manager)

    patch admin_import_review_path(@review), params: { commerce_review: { status: "rejected" } }

    assert_redirected_to admin_import_product_path(@product)
    assert_equal "rejected", @review.reload.status
  end

  test "an invalid review status is rejected without changing the row" do
    sign_in_as(@ops_manager)

    patch admin_import_review_path(@review), params: { commerce_review: { status: "banana" } }

    assert_response :redirect
    assert_equal "approved", @review.reload.status
  end

  # ── Scope: imported rows only ────────────────────────────────────────

  test "stores that were not imported are out of scope" do
    sign_in_as(@ops_manager)

    get admin_import_storefront_path(@plain_storefront)
    assert_response :not_found

    patch admin_import_storefront_path(@plain_storefront),
      params: { commerce_storefront: { display_name: "Nope" } }
    assert_response :not_found
    assert_equal "Plain Store", @plain_storefront.reload.display_name
  end

  test "listings that were not imported are out of scope" do
    sign_in_as(@ops_manager)

    get admin_import_product_path(@plain_product)
    assert_response :not_found

    patch admin_import_product_path(@plain_product),
      params: { commerce_product: { status: "archived" } }
    assert_response :not_found
    assert_equal "active", @plain_product.reload.status
  end

  test "reviews that were not imported are out of scope" do
    sign_in_as(@ops_manager)

    patch admin_import_review_path(@plain_review), params: { commerce_review: { status: "rejected" } }
    assert_response :not_found
    assert_equal "pending", @plain_review.reload.status
  end

  # ── Filters ──────────────────────────────────────────────────────────

  test "listings can be filtered by platform, status and search term" do
    sign_in_as(@ops_manager)

    get admin_import_products_path(platform: "konga")
    assert_response :success
    assert_no_match "Ankara Print Dress", response.body

    get admin_import_products_path(status: "draft")
    assert_no_match "Ankara Print Dress", response.body

    get admin_import_products_path(query: "ankara")
    assert_match "Ankara Print Dress", response.body

    get admin_import_products_path(query: "%' OR 1=1 --")
    assert_response :success
    assert_no_match "Ankara Print Dress", response.body
  end

  test "stores can be filtered by kind" do
    sign_in_as(@ops_manager)

    get admin_import_storefronts_path(kind: "brand")
    assert_response :success
    assert_no_match "Coutures", response.body

    get admin_import_storefronts_path(kind: "seller")
    assert_match "Coutures", response.body
  end

  # ── Platform merchant that owns imported catalogs ─────────────────────

  test "an operator can create the platform merchant that owns imported stores" do
    sign_in_as(@ops_manager)

    post admin_import_system_merchant_path

    assert_redirected_to admin_imports_path
    merchant = CommerceMerchant.system_owned.first
    assert_not_nil merchant
    assert_equal CommerceMerchant::SYSTEM_MERCHANT_ID, merchant.merchant_id
  end

  test "support cannot create the platform merchant" do
    sign_in_as(@support)

    post admin_import_system_merchant_path

    assert_redirected_to admin_dashboard_path
    assert_nil CommerceMerchant.system_owned.first
  end

  test "the imports dashboard names the platform merchant when it exists" do
    CommerceMerchant.system_merchant
    sign_in_as(@ops_manager)

    get admin_imports_path

    assert_response :success
    assert_match CommerceMerchant::SYSTEM_MERCHANT_NAME, response.body
    assert_match CommerceMerchant::SYSTEM_MERCHANT_ID, response.body
  end

  private

  def sign_in_as(user)
    post admin_login_path, params: {
      matrix_user_id: user.matrix_user_id,
      admin_token: ENV["ADMIN_ACCESS_TOKEN"]
    }
    assert_redirected_to admin_dashboard_path, "expected #{user.platform_role} to sign in"
  end

  def create_admin(username, role)
    user = create_user(username)
    user.update!(platform_role: role)
    user
  end

  def create_user(username)
    User.create!(
      matrix_user_id: "@#{username}:example.com",
      matrix_username: "#{username}:example.com",
      matrix_homeserver: "example.com"
    )
  end
end
