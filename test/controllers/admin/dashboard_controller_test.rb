# frozen_string_literal: true

require "test_helper"

# The dashboard is the first screen every operator loads, and it counts across
# every feature on the platform. A model whose table is missing must not cost
# the whole page — that is how a swallowed SQL error took the commerce numbers
# with it.
class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    suffix = SecureRandom.hex(4)
    @system_merchant = CommerceMerchant.system_merchant
    @buyer = create_user("dashboard-buyer-#{suffix}")

    @order = CommerceOrder.create!(
      commerce_merchant: @system_merchant,
      buyer_user_id: @buyer.matrix_user_id,
      payment_id: "pay_dashboard_#{suffix}",
      status: "paid",
      fulfillment_status: "unfulfilled",
      currency: "NGN",
      total_cents: 420_00
    )

    @ops_manager = create_admin("dashboard-ops-#{suffix}", :operations_manager)
    @super_admin = create_admin("dashboard-super-#{suffix}", :super_admin)
  end

  test "anonymous visitors are sent to the admin login" do
    get admin_dashboard_path
    assert_redirected_to admin_login_path
  end

  test "the dashboard renders for platform staff" do
    sign_in_as(@ops_manager)

    get admin_dashboard_path

    assert_response :success
    assert_match "Commerce operations", response.body
  end

  test "a model without a table does not take the metrics down with it" do
    # `group_gifts` has no table in any environment we run, so the dashboard
    # probes before it counts. Without the probe the failed statement aborted
    # the transaction and every metric after it failed too.
    assert_not ActiveRecord::Base.connection.table_exists?("group_gifts"),
      "this test assumes GroupGift has no table; give it one and re-point the test"

    sign_in_as(@super_admin)

    get admin_dashboard_path

    assert_response :success
    assert_match "Commerce operations", response.body
    assert_match "Needs fulfilment", response.body
  end

  test "scope grants are listed with the mini app they belong to" do
    # This panel 500'd in production: the approval's `miniapp` association
    # looked for a class that does not exist, which no test caught while the
    # panel was permanently empty.
    mini_app = MiniApp.create!(
      app_id: "ma_dashboard#{SecureRandom.hex(4)}",
      name: "Dashboard Test App",
      version: "1.0.0",
      classification: :official,
      status: :active,
      manifest: { "scopes" => [ "user:read" ] }
    )
    AuthorizationApproval.create!(
      user_id: @buyer.matrix_user_id,
      miniapp_id: mini_app.app_id,
      scope: "user:read",
      approved_at: Time.current
    )

    sign_in_as(@super_admin)

    get admin_dashboard_path

    assert_response :success
    assert_match "Recent scope grants", response.body
    assert_match "Dashboard Test App", response.body
  end

  test "the layout counts the queue once and shows it in both places" do
    sign_in_as(@super_admin)

    get admin_dashboard_path

    assert_response :success
    assert_match "orders need attention", response.body
  end

  test "the newest users and stores are listed" do
    sign_in_as(@super_admin)

    get admin_dashboard_path

    assert_response :success
    # These panels used to render "No users yet" forever: the helper behind
    # them handed back an empty relation on the happy path.
    assert_match @ops_manager.matrix_user_id, response.body
    assert_match @buyer.matrix_user_id, response.body
  end

  test "orders that need a human are surfaced" do
    sign_in_as(@super_admin)

    get admin_dashboard_path

    assert_response :success
    assert_match "need a human", response.body
    assert_match @buyer.matrix_user_id, response.body
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
