# frozen_string_literal: true

require "test_helper"
require "minitest/mock"
require "tempfile"

# The catalogue desk: correcting listings and pricing variants.
class Admin::ProductsControllerTest < ActionDispatch::IntegrationTest
  setup do
    suffix = SecureRandom.hex(4)
    @merchant = CommerceMerchant.system_merchant
    @category = CommerceCategory.create!(name: "Fashion #{suffix}", slug: "fashion-#{suffix}")
    @child = CommerceCategory.create!(name: "Dresses #{suffix}", slug: "dresses-#{suffix}", parent_id: @category.id)

    @storefront = @merchant.commerce_storefronts.create!(
      display_name: "Bella's Coutures",
      slug: "bellas-#{suffix}",
      status: "published",
      store_type: "ecommerce",
      source_platform: "konga",
      source_kind: "seller",
      source_id: "bellas-#{suffix}"
    )

    @product = @merchant.commerce_products.create!(
      title: "Ankara Print Dress",
      commerce_storefront: @storefront,
      commerce_category: @category,
      status: "active",
      media_urls: [],
      source_platform: "konga",
      source_id: "SKU-#{suffix}",
      source_url: "https://www.konga.com/product/#{suffix}",
      source_payload: { "brand" => "Bella" },
      specifications: { "material" => "Cotton" },
      identifiers: { "sku" => "SKU-#{suffix}" }
    )
    @sku = @product.commerce_skus.create!(title: "Medium", price_cents: 1_250_000, currency: "NGN", quantity_available: 2)

    @uncategorised = @merchant.commerce_products.create!(
      title: "No Category Item #{suffix}",
      commerce_storefront: @storefront,
      media_urls: [],
      status: "draft"
    )

    @ops_manager = create_admin("admin-catalog-ops-#{suffix}", :operations_manager)
    @support = create_admin("admin-catalog-support-#{suffix}", :support)
    @super_admin = create_admin("admin-catalog-super-#{suffix}", :super_admin)
  end

  test "anonymous visitors are sent to the admin login" do
    get admin_products_path
    assert_redirected_to admin_login_path
  end

  test "support can browse the catalogue but not edit it" do
    sign_in_as(@support)

    get admin_products_path
    assert_response :success
    assert_match "Ankara Print Dress", response.body

    patch admin_product_path(@product), params: { commerce_product: { title: "Hijacked" } }
    assert_redirected_to admin_dashboard_path
    assert_equal "Ankara Print Dress", @product.reload.title
  end

  test "the index filters by origin, gaps and category branch" do
    sign_in_as(@super_admin)

    get admin_products_path, params: { origin: "own" }
    assert_response :success
    assert_match "No Category Item", response.body
    refute_match "Ankara Print Dress", response.body

    get admin_products_path, params: { missing: "category" }
    assert_match "No Category Item", response.body
    refute_match "Ankara Print Dress", response.body

    # A parent category also matches listings filed on its child branch.
    @product.update!(subcategory_id: @child.id, category_id: @product.category_id)
    get admin_products_path, params: { category: @category.id }
    assert_match "Ankara Print Dress", response.body
  end

  test "the detail page shows variants, media, provenance and source detail" do
    sign_in_as(@ops_manager)

    get admin_product_path(@product)

    assert_response :success
    assert_match "Listing settings", response.body
    assert_match "Variants (SKUs)", response.body
    assert_match "Medium", response.body
    assert_match "Cotton", response.body
    assert_match "konga", response.body
  end

  test "an operator corrects copy, status and the category" do
    sign_in_as(@ops_manager)

    patch admin_product_path(@product), params: {
      commerce_product: {
        title: "Ankara Print Dress (Lagos)",
        status: "archived",
        category_id: @category.id,
        subcategory_id: @child.id,
        tags: "ankara, dress , lagos"
      }
    }

    assert_redirected_to admin_product_path(@product)
    @product.reload
    assert_equal "Ankara Print Dress (Lagos)", @product.title
    assert_equal "archived", @product.status
    assert_equal @child.id, @product.subcategory_id
    assert_equal [ "ankara", "dress", "lagos" ], @product.tags
  end

  test "an invalid listing change re-renders the form instead of saving" do
    sign_in_as(@ops_manager)

    patch admin_product_path(@product), params: { commerce_product: { status: "banana" } }

    assert_response :unprocessable_entity
    assert_equal "active", @product.reload.status
  end

  test "a variant's price and stock can be corrected" do
    sign_in_as(@ops_manager)

    patch admin_product_sku_path(@product, @sku), params: {
      commerce_sku: { price: "13500.50", quantity_available: 9, inventory_status: "in_stock" }
    }

    assert_redirected_to admin_product_path(@product)
    @sku.reload
    assert_equal 1_350_050, @sku.price_cents
    assert_equal 9, @sku.quantity_available
  end

  test "a variant price that is not a number is refused" do
    sign_in_as(@ops_manager)

    patch admin_product_sku_path(@product, @sku), params: { commerce_sku: { price: "free" } }

    follow_redirect!
    assert_match "Price must be a number", response.body
    assert_equal 1_250_000, @sku.reload.price_cents
  end

  test "an operator adds an image to a listing with none" do
    sign_in_as(@ops_manager)
    url = "https://fs.tween.im/tween/commerce/products/konga/sku-123/media-abc.png"
    file = upload_fixture("shot.png")

    with_uploader_stub(url) do
      post media_admin_product_path(@product), params: { image: file }
    end

    assert_redirected_to admin_product_path(@product)
    assert_equal [ url ], @product.reload.media_urls
  end

  test "an operator removes a dead image" do
    sign_in_as(@ops_manager)
    @product.update!(media_urls: [ "https://cdn.example/dead.jpg", "https://cdn.example/good.jpg" ])

    post media_admin_product_path(@product), params: { remove_url: "https://cdn.example/dead.jpg" }

    assert_equal [ "https://cdn.example/good.jpg" ], @product.reload.media_urls
  end

  private

  def with_uploader_stub(url)
    fake = Object.new
    fake.define_singleton_method(:put) { |**| url }
    fake.define_singleton_method(:put_media) { |**| url }
    original = Commerce::AssetUploader.method(:new)
    Commerce::AssetUploader.define_singleton_method(:new) { |*| fake }
    yield
  ensure
    Commerce::AssetUploader.define_singleton_method(:new, original)
  end

  def upload_fixture(filename)
    @upload_files ||= []
    file = Tempfile.new([ "upload", File.extname(filename) ])
    file.write("not-really-a-png")
    file.rewind
    @upload_files << file
    Rack::Test::UploadedFile.new(file.path, "image/png", original_filename: filename)
  end

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
