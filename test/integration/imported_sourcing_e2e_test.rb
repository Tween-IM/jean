# frozen_string_literal: true

require "test_helper"

# The whole point of the mirrored catalogue: we hold none of it, so a listing
# is only ever bought because a buyer paid for it, and the sourcing desk has to
# be able to walk that purchase to the buyer's door.
#
# This walks the real endpoints end to end -- buyer checks out over the commerce
# API, pays, the platform's own purchase appears on the sourcing desk, staff
# work it to delivered, and the order closes itself.
class ImportedSourcingE2ETest < ActionDispatch::IntegrationTest
  setup do
    @suffix = SecureRandom.hex(4)
    @merchant = CommerceMerchant.system_merchant

    @storefront = @merchant.commerce_storefronts.create!(
      display_name: "Bella's Coutures #{@suffix}",
      slug: "bellas-coutures-#{@suffix}",
      status: "published",
      store_type: "ecommerce",
      source_platform: "konga",
      source_kind: "seller",
      source_id: "bellas-#{@suffix}"
    )
    @product = @merchant.commerce_products.create!(
      title: "Ankara Print Dress #{@suffix}",
      commerce_storefront: @storefront,
      status: "active",
      source_platform: "konga",
      source_id: "SKU-#{@suffix}",
      source_url: "https://www.konga.com/product/SKU-#{@suffix}",
      brand: "Bella Couture",
      supplier_name: "Chimaco Stores",
      supplier_id: "8811",
      supplier_platform: "konga",
      supplier_url: "https://www.konga.com/product/SKU-#{@suffix}",
      source_price_cents: 900_000
    )
    @sku = @product.commerce_skus.create!(
      title: "Medium", price_cents: 1_250_000, currency: "NGN", quantity_available: 4
    )

    @buyer = create_user("sourcing-e2e-buyer-#{@suffix}")
    @cart = @merchant.commerce_carts.create!(buyer_user_id: @buyer.matrix_user_id, currency: "NGN")
    @cart.commerce_cart_items.create!(commerce_sku: @sku, quantity: 1)

    @ops_manager = create_admin("sourcing-e2e-ops-#{@suffix}", :operations_manager)
    @analyst = create_admin("sourcing-e2e-analyst-#{@suffix}", :operations_analyst)
  end

  test "a buyer pays, the desk sources it, and the order closes itself" do
    checkout = create_checkout

    # A checkout that has not been paid for is not a purchase. Nothing has been
    # committed to a supplier, and the desk has nothing to do yet.
    order = checkout_order
    assert_equal "pending_payment", order.status
    assert_equal 0, CommerceProcurement.count

    sign_in_as(@analyst)
    get admin_procurements_path
    assert_match "Nothing to source", response.body

    authorize(checkout)

    order.reload
    assert_equal "paid", order.status
    assert_equal "unfulfilled", order.fulfillment_status

    procurement = order.commerce_procurements.reload.first
    assert_not_nil procurement, "paying for an imported listing has to queue the purchase"
    assert_equal "pending", procurement.status
    assert_equal "Chimaco Stores", procurement.supplier_name
    assert_equal "konga", procurement.supplier_platform
    assert_equal "https://www.konga.com/product/SKU-#{@suffix}", procurement.supplier_url
    assert_equal "NGN", procurement.currency

    # The desk sees what to buy, from whom, and where to buy it.
    post admin_logout_path if false
    get admin_procurements_path
    assert_response :success
    assert_match @product.title, response.body
    assert_match "Chimaco Stores", response.body

    # Walk the purchase: bought at the source, then received, shipped, delivered.
    sign_in_as(@ops_manager)
    advance(procurement, "ordered", cost_cents: 900_000, external_order_ref: "KNG-#{@suffix}")
    assert_equal "partially_fulfilled", order.reload.fulfillment_status

    advance(procurement, "received")
    advance(procurement, "dispatched", courier: "GIG", tracking_number: "GIG-#{@suffix}")
    advance(procurement, "delivered")

    procurement.reload
    assert_equal "delivered", procurement.status
    assert_equal 900_000, procurement.cost_cents
    assert_equal "KNG-#{@suffix}", procurement.external_order_ref
    assert_equal "GIG-#{@suffix}", procurement.tracking_number
    assert_equal @ops_manager.matrix_user_id, procurement.started_by_user_id

    order.reload
    assert_equal "fulfilled", order.fulfillment_status
    assert_equal "fulfilled", order.status

    # What the buyer paid above what we paid to source it.
    margin = order.total_cents - procurement.cost_cents
    assert_equal 350_000, margin

    get admin_procurement_path(procurement)
    assert_response :success
    assert_match "Delivered", response.body
  end

  test "an abandoned checkout never reaches the sourcing desk" do
    checkout = create_checkout
    assert_equal 0, CommerceProcurement.count

    post cancel_api_v1_commerce_checkout_url(checkout.checkout_id),
      headers: tep_headers(@buyer, "commerce:checkout"),
      as: :json

    assert_response :success
    assert_equal "cancelled", checkout_order.reload.status
    assert_equal 0, CommerceProcurement.count

    sign_in_as(@analyst)
    get admin_procurements_path
    assert_match "Nothing to source", response.body
  end

  test "a refund after delivery does not un-deliver what the buyer has" do
    checkout = create_checkout
    authorize(checkout)
    order = checkout_order
    procurement = order.commerce_procurements.reload.first

    advance(procurement, "ordered")
    advance(procurement, "received")
    advance(procurement, "dispatched")
    advance(procurement, "delivered")

    order.update!(status: "refunded")

    assert_equal "delivered", procurement.reload.status
    assert_equal 0, CommerceProcurement.open.count
  end

  private

  def create_checkout
    with_wallet_stub(:create_payment_request, { payment_id: "pay_e2e_#{@suffix}", status: "created" }) do
      post api_v1_commerce_checkouts_url,
        params: { cart_id: @cart.cart_id, shipping_address: { city: "Lagos", state: "Lagos", country: "NG", phone: "+2348000000000" } },
        headers: tep_headers(@buyer, "commerce:checkout"),
        as: :json
    end

    assert_response :created
    CommerceCheckout.find_by!(checkout_id: response.parsed_body.dig("checkout", "checkout_id"))
  end

  def authorize(checkout)
    with_wallet_stub(:authorize_payment, { "status" => "completed", "txn_id" => "txn_e2e_#{@suffix}" }) do
      post authorize_api_v1_commerce_checkout_url(checkout.checkout_id),
        params: { authorization: { signature: "test_sig", device_id: "device_e2e", timestamp: (Time.current.to_f * 1000).to_i.to_s }, payment_method: "wallet" },
        headers: tep_headers(@buyer, "commerce:checkout"),
        as: :json
    end

    assert_response :success
  end

  def checkout_order
    CommerceOrder.find_by!(order_id: CommerceCheckout.find_by(order_id: nil) || last_checkout_order_id)
  rescue ActiveRecord::RecordNotFound
    CommerceOrder.order(:id).last
  end

  def last_checkout_order_id
    CommerceCheckout.order(:id).last.order_id
  end

  def advance(procurement, status, **attributes)
    sign_in_as(@ops_manager)
    post advance_admin_procurement_path(procurement),
      params: { status: status, commerce_procurement: attributes }

    assert_redirected_to admin_procurement_path(procurement), "expected #{status} to be accepted"
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

  def tep_headers(user, scopes)
    token = TepTokenService.encode({ user_id: user.matrix_user_id, miniapp_id: "miniapp.shop.test" }, scopes: scopes.split)
    { "Authorization" => "Bearer #{token}" }
  end

  def with_wallet_stub(method_name, response)
    original = WalletService.method(method_name)
    WalletService.define_singleton_method(method_name) { |*, **| response }
    yield
  ensure
    WalletService.define_singleton_method(method_name, original)
  end
end
