# frozen_string_literal: true

require "test_helper"
require "minitest/mock"
require "tempfile"

# Storefront management: branding an operator has to supply by hand, because
# the mirrored marketplaces publish no logos.
class Admin::StorefrontsControllerTest < ActionDispatch::IntegrationTest
  setup do
    suffix = SecureRandom.hex(4)
    @merchant = CommerceMerchant.system_merchant

    @storefront = @merchant.commerce_storefronts.create!(
      display_name: "Bella's Coutures",
      slug: "bellas-coutures-#{suffix}",
      status: "published",
      store_type: "ecommerce",
      source_platform: "konga",
      source_kind: "seller",
      source_id: "bellas-#{suffix}",
      source_url: "https://www.konga.com/seller/bellas",
      source_synced_at: 2.hours.ago,
      source_payload: { "seller" => { "name" => "Bella's Coutures", "banner" => "https://cdn.konga/banner.jpg" } }
    )
    @product = @merchant.commerce_products.create!(
      title: "Ankara Print Dress",
      commerce_storefront: @storefront,
      status: "active",
      source_platform: "konga",
      source_id: "SKU-#{suffix}"
    )

    @ops_manager = create_admin("admin-stores-ops-#{suffix}", :operations_manager)
    @support = create_admin("admin-stores-support-#{suffix}", :support)
    @super_admin = create_admin("admin-stores-super-#{suffix}", :super_admin)
  end

  test "anonymous visitors are sent to the admin login" do
    get admin_storefronts_path
    assert_redirected_to admin_login_path
  end

  test "support can look at stores but not change them" do
    sign_in_as(@support)

    get admin_storefronts_path
    assert_response :success
    assert_match "Bella", response.body

    patch admin_storefront_path(@storefront), params: { commerce_storefront: { display_name: "Hijacked" } }
    assert_redirected_to admin_dashboard_path
    assert_equal "Bella's Coutures", @storefront.reload.display_name
  end

  test "the index reports branding gaps" do
    sign_in_as(@super_admin)

    get admin_storefronts_path, params: { missing: "logo" }

    assert_response :success
    assert_match "No logo", response.body
    assert_match "Bella", response.body
  end

  test "the detail page shows branding, provenance and the contact queue" do
    sign_in_as(@ops_manager)

    get admin_storefront_path(@storefront)

    assert_response :success
    assert_match "Store settings", response.body
    assert_match "No contact on file", response.body
    assert_match "konga", response.body
    assert_match "Ankara Print Dress", response.body
  end

  test "an operator records branding, contact details and visibility" do
    sign_in_as(@ops_manager)

    patch admin_storefront_path(@storefront), params: {
      commerce_storefront: {
        display_name: "Bella Couture",
        about: "Lagos-made occasion wear.",
        accent_color: "#123456",
        status: "published",
        featured: "1",
        contact_phone: "+234 801 000 0000",
        contact_email: "hello@bella.example"
      }
    }

    assert_redirected_to admin_storefront_path(@storefront)
    @storefront.reload
    assert_equal "Bella Couture", @storefront.display_name
    assert_equal "#123456", @storefront.accent_color
    assert @storefront.featured
    assert_equal "hello@bella.example", @storefront.contact_email
  end

  test "an uploaded logo is stored and published on the storefront" do
    sign_in_as(@ops_manager)
    url = "https://fs.tween.im/tween/commerce/storefronts/konga/seller/bellas/logo-abc123.png"
    file = upload_fixture("logo.png")

    with_uploader_stub(url) do
      patch admin_storefront_path(@storefront), params: {
        commerce_storefront: { display_name: @storefront.display_name, logo: file }
      }
    end

    assert_redirected_to admin_storefront_path(@storefront)
    assert_equal url, @storefront.reload.logo_url
  end

  test "an invalid change re-renders the form instead of saving" do
    sign_in_as(@ops_manager)

    patch admin_storefront_path(@storefront), params: { commerce_storefront: { accent_color: "not-a-colour" } }

    assert_response :unprocessable_entity
    assert_match "Store settings", response.body
    assert_equal "#7C3AED", @storefront.reload.accent_color
  end

  test "an uploader failure is reported and nothing is written" do
    sign_in_as(@ops_manager)
    file = upload_fixture("logo.png")

    with_uploader_failure("the bucket said no") do
      patch admin_storefront_path(@storefront), params: {
        commerce_storefront: { display_name: @storefront.display_name, logo: file }
      }
    end

    assert_response :unprocessable_entity
    assert_match "the bucket said no", response.body
    assert_nil @storefront.reload.logo_url
  end

  test "enrich pulls branding out of the store's own listings" do
    sign_in_as(@ops_manager)
    calls = []

    Commerce::StorefrontBrandingBackfill.stub(:call, ->(dry_run:, only: nil) {
      calls << { dry_run: dry_run, only: only }
      Commerce::StorefrontBrandingBackfill::Summary.new(
        stores_scanned: 1, stores_filled: 1, banners: 1, addresses: 0, accents: 0
      )
    }) do
      post enrich_admin_storefront_path(@storefront)
    end

    assert_redirected_to admin_storefront_path(@storefront)
    assert_equal false, calls.first[:dry_run]
    assert_equal @storefront.id, calls.first[:only].id
    follow_redirect!
    assert_match "banner", response.body
  end

  test "featuring a store toggles the flag" do
    sign_in_as(@ops_manager)

    post feature_admin_storefront_path(@storefront)
    assert @storefront.reload.featured

    post feature_admin_storefront_path(@storefront)
    assert_not @storefront.reload.featured
  end

  private

  def with_uploader_stub(url)
    fake = Object.new
    fake.define_singleton_method(:put) { |**| url }
    fake.define_singleton_method(:put_media) { |**| url }
    swap_uploader(fake) { yield }
  end

  def with_uploader_failure(message)
    fake = Object.new
    fake.define_singleton_method(:put) { |**| raise Commerce::AssetUploader::Error, message }
    fake.define_singleton_method(:put_media) { |**| raise Commerce::AssetUploader::Error, message }
    swap_uploader(fake) { yield }
  end

  def swap_uploader(fake)
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
