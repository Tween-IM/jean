# frozen_string_literal: true

require "test_helper"

class Admin::MerchantsControllerTest < ActionDispatch::IntegrationTest
  setup do
    suffix = SecureRandom.hex(4)
    @system_merchant = CommerceMerchant.system_merchant
    @owner = create_user("admin-merchant-owner-#{suffix}")
    @merchant = CommerceMerchant.create!(
      owner_user_id: @owner.matrix_user_id,
      miniapp_id: "miniapp.merchant.test",
      display_name: "Bella's Boutique",
      status: "pending_review",
      business_type: "individual"
    )
    @storefront = @merchant.commerce_storefronts.create!(
      display_name: "Bella's Boutique",
      slug: "bellas-boutique-#{suffix}",
      status: "draft",
      store_type: "ecommerce"
    )
    @order = CommerceOrder.create!(
      commerce_merchant: @merchant,
      buyer_user_id: "@buyer-merchant-#{suffix}:example.com",
      payment_id: "pay_merchant_#{suffix}",
      status: "paid",
      currency: "NGN",
      total_cents: 250_00
    )

    @ops_manager = create_admin("admin-merchants-ops-#{suffix}", :operations_manager)
    @support = create_admin("admin-merchants-support-#{suffix}", :support)
    @super_admin = create_admin("admin-merchants-super-#{suffix}", :super_admin)
  end

  test "anonymous visitors are sent to the admin login" do
    get admin_merchants_path
    assert_redirected_to admin_login_path
  end

  test "support can look at merchants but not verify them" do
    sign_in_as(@support)

    get admin_merchants_path
    assert_response :success
    assert_match "Bella&#39;s Boutique", response.body

    post verify_admin_merchant_path(@merchant)
    assert_redirected_to admin_dashboard_path
    assert_nil @merchant.reload.verified_at
  end

  test "the index can isolate the system merchant" do
    sign_in_as(@super_admin)

    get admin_merchants_path, params: { ownership: "system" }

    assert_response :success
    assert_match CommerceMerchant::SYSTEM_MERCHANT_NAME, response.body
    refute_match "Bella&#39;s Boutique", response.body
  end

  test "the detail page shows the owner, stores, orders and terms" do
    sign_in_as(@ops_manager)

    get admin_merchant_path(@merchant)

    assert_response :success
    assert_match "Bella&#39;s Boutique", response.body
    assert_match @owner.matrix_user_id, response.body
    assert_match "Bella&#39;s Boutique", response.body
    assert_match "Commerce", response.body
  end

  test "an operator updates the commercial terms" do
    sign_in_as(@ops_manager)

    patch admin_merchant_path(@merchant), params: {
      commerce_merchant: { display_name: "Bella Boutique Ltd", commission_rate: 750, email: "ops@bella.example" }
    }

    assert_redirected_to admin_merchant_path(@merchant)
    @merchant.reload
    assert_equal "Bella Boutique Ltd", @merchant.display_name
    assert_equal 750, @merchant.commission_rate
    assert_equal "ops@bella.example", @merchant.email
  end

  test "verifying a merchant activates it and stamps the date" do
    sign_in_as(@ops_manager)

    post verify_admin_merchant_path(@merchant)

    @merchant.reload
    assert_not_nil @merchant.verified_at
    assert_equal "active", @merchant.status
  end

  test "suspending and reactivating flips the status" do
    sign_in_as(@ops_manager)

    post suspend_admin_merchant_path(@merchant)
    assert_equal "suspended", @merchant.reload.status

    post reactivate_admin_merchant_path(@merchant)
    assert_equal "active", @merchant.reload.status
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
