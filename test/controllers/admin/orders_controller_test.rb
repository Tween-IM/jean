# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# The admin order desk. The point of these tests is that platform staff can
# actually move an order the platform owns — the system merchant has no human
# owner, so the seller-side guards would otherwise reject every action.
class Admin::OrdersControllerTest < ActionDispatch::IntegrationTest
  setup do
    suffix = SecureRandom.hex(4)

    @system_merchant = CommerceMerchant.system_merchant
    @system_store = @system_merchant.commerce_storefronts.create!(
      display_name: "Bella's Coutures",
      slug: "bellas-coutures-#{suffix}",
      status: "published",
      store_type: "ecommerce",
      source_platform: "konga",
      source_kind: "seller",
      source_id: "bellas-#{suffix}"
    )

    @product = @system_merchant.commerce_products.create!(
      title: "Ankara Print Dress",
      commerce_storefront: @system_store,
      status: "active",
      source_platform: "konga",
      source_id: "SKU-#{suffix}",
      source_url: "https://www.konga.com/product/SKU-#{suffix}",
      brand: "Bella Couture",
      supplier_name: "Chimaco Stores",
      supplier_id: "8811",
      supplier_platform: "konga",
      source_price_cents: 900_000
    )
    @sku = @product.commerce_skus.create!(
      title: "Medium",
      price_cents: 1_250_000,
      currency: "NGN",
      quantity_available: 4
    )

    @buyer = create_user("admin-order-buyer-#{suffix}")

    @order = CommerceOrder.create!(
      commerce_merchant: @system_merchant,
      buyer_user_id: @buyer.matrix_user_id,
      payment_id: "pay_admin_#{suffix}",
      protected_payment_id: "ppay_admin_#{suffix}",
      status: "paid",
      protection_status: "active",
      fulfillment_status: "unfulfilled",
      currency: "NGN",
      subtotal_cents: @sku.price_cents,
      total_cents: @sku.price_cents
    )
    @order.commerce_order_items.create!(
      sku_id: @sku.sku_id,
      product_id: @product.product_id,
      title: @sku.title,
      quantity: 1,
      unit_price_cents: @sku.price_cents,
      line_total_cents: @sku.price_cents,
      currency: "NGN"
    )

    @unpaid = CommerceOrder.create!(
      commerce_merchant: @system_merchant,
      buyer_user_id: @buyer.matrix_user_id,
      payment_id: "pay_admin_unpaid_#{suffix}",
      status: "pending_payment",
      currency: "NGN",
      total_cents: 500_00
    )

    @super_admin = create_admin("admin-orders-super-#{suffix}", :super_admin)
    @ops_manager = create_admin("admin-orders-ops-#{suffix}", :operations_manager)
    @support = create_admin("admin-orders-support-#{suffix}", :support)
    @analyst = create_admin("admin-orders-analyst-#{suffix}", :operations_analyst)
  end

  # ── Who may look, who may act ────────────────────────────────────────

  test "anonymous visitors are sent to the admin login" do
    get admin_orders_path
    assert_redirected_to admin_login_path
  end

  test "support and analysts can see the order book" do
    [ @support, @analyst ].each do |admin|
      sign_in_as(admin)

      get admin_orders_path
      assert_response :success
      assert_match @order.order_id, response.body
      assert_match "Need", response.body
    end
  end

  test "support cannot change an order" do
    sign_in_as(@support)

    post transition_admin_order_path(@order), params: { status: "processing" }

    assert_redirected_to admin_dashboard_path
    assert_equal "paid", @order.reload.status
  end

  test "support cannot refund an order" do
    sign_in_as(@support)

    post refund_admin_order_path(@order), params: { amount_cents: 100 }

    assert_redirected_to admin_dashboard_path
    assert_equal "paid", @order.reload.status
  end

  # ── Reading the order ────────────────────────────────────────────────

  test "the detail page shows items, buyer, merchant and the next legal moves" do
    sign_in_as(@ops_manager)

    get admin_order_path(@order)

    assert_response :success
    assert_match "Ankara Print Dress", response.body
    assert_match @buyer.matrix_user_id, response.body
    assert_match "system merchant", response.body
    assert_match "Move the order", response.body
    assert_match "Processing", response.body
    assert_match "Sync from Tween Pay", response.body
    # The desk has to know where the goods come from and what they cost us:
    # the supplier is frozen onto the line, not read off the listing.
    assert_match "Chimaco Stores", response.body
    assert_match "At source", response.body
  end

  test "the index narrows by status, merchant and attention" do
    sign_in_as(@ops_manager)

    get admin_orders_path, params: { status: "pending_payment" }
    assert_response :success
    assert_match @unpaid.order_id, response.body
    refute_match @order.order_id, response.body

    get admin_orders_path, params: { merchant: "system" }
    assert_response :success
    assert_match @order.order_id, response.body

    get admin_orders_path, params: { attention: "1" }
    assert_response :success
    assert_match @order.order_id, response.body
    assert_match @unpaid.order_id, response.body
  end

  test "search matches the order id" do
    sign_in_as(@analyst)

    get admin_orders_path, params: { query: @order.order_id }

    assert_response :success
    assert_match @order.order_id, response.body
    refute_match @unpaid.order_id, response.body
  end

  # ── Moving the order ─────────────────────────────────────────────────

  test "an operations manager moves an order along a legal transition" do
    sign_in_as(@ops_manager)

    post transition_admin_order_path(@order), params: { status: "processing" }

    assert_redirected_to admin_order_path(@order)
    assert_equal "processing", @order.reload.status
    assert_equal "transition", @order.metadata["timeline"].last["action"]
    assert_equal @ops_manager.matrix_user_id, @order.metadata["timeline"].last["by"]
  end

  test "an illegal transition is refused and leaves the order alone" do
    sign_in_as(@ops_manager)

    post transition_admin_order_path(@unpaid), params: { status: "fulfilled" }

    assert_redirected_to admin_order_path(@unpaid)
    assert_equal "pending_payment", @unpaid.reload.status
    follow_redirect!
    assert_match "not a legal order transition", response.body
  end

  test "merging into a fulfilled state settles the fulfilment status too" do
    sign_in_as(@ops_manager)

    post transition_admin_order_path(@order), params: { status: "fulfilled" }

    @order.reload
    assert_equal "fulfilled", @order.status
    assert_equal "fulfilled", @order.fulfillment_status
  end

  # ── Fulfilment as the platform ───────────────────────────────────────

  test "platform staff record a shipment on the system merchant's order" do
    sign_in_as(@ops_manager)

    post fulfillment_admin_order_path(@order),
      params: { fulfillment_action: "ship", carrier: "GIG", tracking_number: "GIG-1" }

    assert_redirected_to admin_order_path(@order)

    fulfillment = @order.reload.commerce_fulfillments.last
    assert_not_nil fulfillment
    assert_equal "shipped", fulfillment.status
    assert_equal "GIG-1", fulfillment.tracking_number
    assert_equal @ops_manager.matrix_user_id, fulfillment.updated_by_user_id
    assert_equal "partially_fulfilled", @order.fulfillment_status
  end

  test "marking delivered then confirming on the buyer's behalf completes the order" do
    sign_in_as(@ops_manager)

    post fulfillment_admin_order_path(@order), params: { fulfillment_action: "deliver", note: "handed to buyer" }
    assert_equal "processing", @order.reload.status

    ProtectedCommerceService.stub(:schedule_release, { "status" => "scheduled" }) do
      post fulfillment_admin_order_path(@order), params: { fulfillment_action: "confirm" }
    end

    @order.reload
    assert_equal "fulfilled", @order.status
    assert_equal "fulfilled", @order.fulfillment_status
    assert_equal "accepted", @order.commerce_fulfillments.last.status
  end

  test "an unknown fulfilment action is refused" do
    sign_in_as(@ops_manager)

    post fulfillment_admin_order_path(@order), params: { fulfillment_action: "teleport" }

    follow_redirect!
    assert_match "Unknown fulfilment action", response.body
    assert_equal 0, @order.reload.commerce_fulfillments.count
  end

  # ── Money ────────────────────────────────────────────────────────────

  test "a protected order refunds through Tween Pay and restores stock" do
    sign_in_as(@ops_manager)
    calls = []
    refund = lambda { |payment_id, amount_cents:, reason:, actor:|
      calls << { payment_id: payment_id, amount_cents: amount_cents, reason: reason, actor: actor }
      { "status" => "refunded" }
    }

    ProtectedCommerceService.stub(:refund, refund) do
      post refund_admin_order_path(@order), params: { amount_cents: @order.total_cents, reason: "not_as_described" }
    end

    assert_redirected_to admin_order_path(@order)
    @order.reload
    assert_equal "refunded", @order.status
    assert_equal 1, @order.metadata["refunds"].size
    assert_equal @ops_manager.matrix_user_id, @order.metadata["refunds"].first["processed_by"]
    assert_equal 5, @sku.reload.quantity_available
    assert_equal 1, calls.size
    assert_equal @ops_manager.matrix_user_id, calls.first[:actor]
  end

  test "a refund larger than the order is refused before any money moves" do
    sign_in_as(@ops_manager)
    called = false

    ProtectedCommerceService.stub(:refund, ->(*, **) { called = true }) do
      post refund_admin_order_path(@order), params: { amount_cents: @order.total_cents + 1 }
    end

    assert_not called
    follow_redirect!
    assert_match "cannot exceed the order total", response.body
    assert_equal "paid", @order.reload.status
  end

  test "a partial refund leaves the order partially refunded" do
    sign_in_as(@ops_manager)

    ProtectedCommerceService.stub(:refund, { "status" => "refunded" }) do
      post refund_admin_order_path(@order), params: { amount_cents: 500_00, reason: "goodwill" }
    end

    assert_equal "partially_refunded", @order.reload.status
  end

  # ── Payments ─────────────────────────────────────────────────────────

  test "the protected payment can be pulled from Tween Pay and kept as a snapshot" do
    sign_in_as(@ops_manager)

    ProtectedCommerceService.stub(:get_payment, { "status" => "funded", "amount_cents" => 1_250_000 }) do
      post payment_admin_order_path(@order)
    end

    assert_redirected_to admin_order_path(@order)
    snapshot = @order.reload.metadata["protected_payment"]
    assert_equal "funded", snapshot["payload"]["status"]
    assert snapshot["synced_at"].present?

    follow_redirect!
    assert_match "funded", response.body
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
