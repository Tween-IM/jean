# frozen_string_literal: true

require "test_helper"

# The sourcing desk. Nothing is bought at import time and nothing is bought
# before a buyer pays, so this queue is the only place a purchase starts, and
# staff have to be able to work it without a merchant account.
class Admin::ProcurementsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @suffix = SecureRandom.hex(4)

    @merchant = CommerceMerchant.system_merchant
    @product = @merchant.commerce_products.create!(
      title: "Imported Blender #{@suffix}",
      status: "active",
      source_platform: "konga",
      source_id: "BLENDER-#{@suffix}",
      source_url: "https://www.konga.com/product/#{@suffix}",
      brand: "Chimaco",
      supplier_name: "Chimaco Stores #{@suffix}",
      supplier_platform: "konga",
      supplier_url: "https://www.konga.com/product/#{@suffix}",
      source_price_cents: 250_00
    )
    @sku = @product.commerce_skus.create!(
      title: "Silver", price_cents: 320_00, currency: "NGN", quantity_available: 5
    )

    @buyer = create_user("procurement-buyer-#{@suffix}")
    @order = CommerceOrder.create!(
      commerce_merchant: @merchant,
      buyer_user_id: @buyer.matrix_user_id,
      payment_id: "pay_procurement_#{@suffix}",
      status: "paid",
      fulfillment_status: "unfulfilled",
      currency: "NGN",
      subtotal_cents: 320_00,
      total_cents: 320_00
    )
    @procurement = @order.commerce_order_items.create!(
      sku_id: @sku.sku_id,
      product_id: @product.product_id,
      title: @product.title,
      quantity: 1,
      unit_price_cents: 320_00,
      line_total_cents: 320_00,
      currency: "NGN"
    ).commerce_procurement

    @support = create_admin("procurements-support-#{@suffix}", :support)
    @analyst = create_admin("procurements-analyst-#{@suffix}", :operations_analyst)
    @ops_manager = create_admin("procurements-ops-#{@suffix}", :operations_manager)
  end

  test "anonymous visitors are sent to the admin login" do
    get admin_procurements_path
    assert_redirected_to admin_login_path
  end

  test "support and analysts can read the queue with what to buy and from whom" do
    [ @support, @analyst ].each do |admin|
      sign_in_as(admin)

      get admin_procurements_path

      assert_response :success
      assert_match @product.title, response.body
      assert_match "Chimaco Stores #{@suffix}", response.body
      assert_match @order.order_id, response.body
      assert_match "To buy", response.body
    end
  end

  test "support cannot buy anything on the platform's behalf" do
    sign_in_as(@support)

    post advance_admin_procurement_path(@procurement), params: { status: "ordered" }

    assert_redirected_to admin_dashboard_path
    assert_equal "pending", @procurement.reload.status
  end

  test "an operations manager records a purchase and the order follows it" do
    sign_in_as(@ops_manager)

    post advance_admin_procurement_path(@procurement),
      params: {
        status: "ordered",
        commerce_procurement: {
          cost_cents: 250_00,
          external_order_ref: "KNG-77412",
          supplier_name: "Chimaco Stores #{@suffix}"
        }
      }

    assert_redirected_to admin_procurement_path(@procurement)

    @procurement.reload
    assert_equal "ordered", @procurement.status
    assert_equal 250_00, @procurement.cost_cents
    assert_equal "KNG-77412", @procurement.external_order_ref
    assert_not_nil @procurement.ordered_at
    assert_equal @ops_manager.matrix_user_id, @procurement.started_by_user_id
    assert_equal "partially_fulfilled", @order.reload.fulfillment_status
  end

  test "an illegal step is refused in the page rather than in an exception" do
    sign_in_as(@ops_manager)

    post advance_admin_procurement_path(@procurement), params: { status: "delivered" }

    assert_redirected_to admin_procurement_path(@procurement)
    follow_redirect!
    assert_match "cannot move to delivered", response.body
    assert_equal "pending", @procurement.reload.status
  end

  test "the buy link goes to the source listing" do
    sign_in_as(@analyst)

    get admin_procurement_path(@procurement)

    assert_response :success
    assert_match "https://www.konga.com/product/#{@suffix}", response.body
    assert_match "Open the listing at source", response.body
  end

  test "the queue opens on what still has to be bought" do
    settled = create_settled_procurement(status: "delivered")
    sign_in_as(@analyst)

    get admin_procurements_path
    assert_response :success
    assert_match @product.title, response.body

    get admin_procurements_path, params: { status: "delivered" }
    assert_response :success
    assert_match settled.commerce_order.order_id, response.body
  end

  test "the queue can be narrowed by marketplace, supplier and age" do
    other = create_procurement_from(
      supplier_name: "Jumia Vendor #{@suffix}", supplier_platform: "jumia"
    )
    sign_in_as(@analyst)

    get admin_procurements_path, params: { platform: "jumia" }
    assert_response :success
    assert_match "Jumia Vendor #{@suffix}", response.body
    refute_match "Chimaco Stores #{@suffix}", response.body

    get admin_procurements_path, params: { query: "Chimaco Stores #{@suffix}" }
    assert_response :success
    assert_match @product.title, response.body
    refute_match other.commerce_order_item.title, response.body

    other.update_columns(created_at: 3.days.ago)
    get admin_procurements_path, params: { aged: "1" }
    assert_response :success
    assert_match other.commerce_order_item.title, response.body
    refute_match @product.title, response.body
  end

  test "the queue counts what is waiting and what has been committed" do
    create_settled_procurement(status: "delivered", cost_cents: 100_00)
    sign_in_as(@analyst)

    get admin_procurements_path

    assert_response :success
    assert_match "nobody has bought it yet", response.body
    assert_match "Committed", response.body
    assert_match "recorded cost to us", response.body
  end

  private

  def create_settled_procurement(status:, cost_cents: nil)
    procurement = create_procurement_from(supplier_name: "Settled Vendor #{@suffix}")
    procurement.update!(
      status: status,
      cost_cents: cost_cents,
      created_at: 2.days.ago
    )
    procurement
  end

  def create_procurement_from(supplier_name:, supplier_platform: "jumia")
    product = @merchant.commerce_products.create!(
      title: "Imported Fan #{SecureRandom.hex(3)}",
      status: "active",
      source_platform: supplier_platform,
      source_id: "FAN-#{SecureRandom.hex(4)}",
      supplier_name: supplier_name,
      supplier_platform: supplier_platform,
      supplier_url: "https://www.#{supplier_platform}.ng/product/x"
    )
    sku = product.commerce_skus.create!(
      title: "White", price_cents: 150_00, currency: "NGN", quantity_available: 2
    )
    order = CommerceOrder.create!(
      commerce_merchant: @merchant,
      buyer_user_id: @buyer.matrix_user_id,
      payment_id: "pay_#{SecureRandom.hex(6)}",
      status: "paid",
      fulfillment_status: "unfulfilled",
      currency: "NGN",
      total_cents: 150_00
    )

    order.commerce_order_items.create!(
      sku_id: sku.sku_id,
      product_id: product.product_id,
      title: product.title,
      quantity: 1,
      unit_price_cents: 150_00,
      line_total_cents: 150_00,
      currency: "NGN"
    ).commerce_procurement
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
