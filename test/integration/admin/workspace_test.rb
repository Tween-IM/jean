require "test_helper"

class Admin::WorkspaceTest < ActionDispatch::IntegrationTest
  setup do
    @staff = User.create!(matrix_user_id: "@workspace_#{SecureRandom.hex(4)}:tween.im",
      matrix_username: "workspace:tween.im", matrix_homeserver: "tween.im", platform_role: "super_admin")
    post admin_login_path, params: { admin_token: ENV["ADMIN_ACCESS_TOKEN"], matrix_user_id: @staff.matrix_user_id }
  end

  test "overview and people are one workspace" do
    get admin_dashboard_path
    assert_response :success
    assert_select "h1", "Overview"
    assert_select ".admin-sidebar", count: 1
    get admin_users_path, params: { query: @staff.matrix_user_id }
    assert_response :success
    assert_select "h1", "People"
    assert_select "td", text: /workspace:tween.im/
    get admin_user_path(@staff)
    assert_response :success
    assert_select ".admin-tab", text: "Payments"
    assert_select "iframe", count: 0
  end

  test "payment failure does not block the profile" do
    get admin_user_path(@staff, tab: "payments")
    assert_response :success
    assert_select "h2", "We couldn’t load this information"
    get admin_user_path(@staff)
    assert_response :success
    assert_select "h2", "Account overview"
  end

  test "payment requests carry signed short lived actor delegation" do
    ENV["TWEEN_PAY_ADMIN_URL"] = "https://pay.test"
    ENV["TWEEN_ADMIN_SECRET"] = "x" * 48
    stub_request(:get, /pay.test\/internal\/admin\/v1\/resources\/wallets/).with do |request|
      token = request.headers.fetch("Authorization").delete_prefix("Bearer ")
      claims, = JWT.decode(token, "x" * 48, true, algorithm: "HS256")
      claims["sub"] == @staff.matrix_user_id && claims["exp"] - claims["iat"] == 60
    end.to_return(body: { records: [{ id: 7, currency: "NGN", balance_cents: 12345, status: "active" }], page: 1, total: 1 }.to_json)
    get admin_resource_path("wallets")
    assert_response :success
    assert_select "td", "NGN 123.45"
  ensure
    ENV.delete("TWEEN_PAY_ADMIN_URL")
    ENV.delete("TWEEN_ADMIN_SECRET")
  end

  test "direct resource requests enforce permissions" do
    @staff.update!(platform_role: "product_manager")
    get admin_resource_path("wallets")
    assert_response :forbidden
    get admin_user_path(@staff, tab: "payments")
    assert_response :forbidden
    post admin_resource_command_path("wallets", 1), params: { operation: "set_status", value: "frozen", reason: "Support case", command_id: SecureRandom.uuid }
    assert_response :forbidden
  end

  test "staff revocation blocks an existing session" do
    @staff.update!(status: "suspended")
    get admin_users_path
    assert_redirected_to admin_login_path
  end

  test "review writes require manage permission" do
    @staff.update!(platform_role: "support")
    post admin_approve_mini_app_review_path(123)
    assert_redirected_to admin_dashboard_path
  end

  test "unknown resources and operations are rejected" do
    get admin_resource_path("secrets")
    assert_response :not_found
    post admin_resource_command_path("rooms", "room"), params: { operation: "set_status", reason: "Support case", command_id: SecureRandom.uuid }
    assert_response :forbidden
  end

  test "audit details recursively remove secrets" do
    safe = AdminAuditEvent.safe_details({ changes: { password: "secret", token: "secret", status: "suspended" } })
    assert_equal({ "changes" => { "status" => "suspended" } }, safe)
  end
  test "payment command records its actor and outcome" do
    ENV["TWEEN_PAY_ADMIN_URL"] = "https://pay.test"
    ENV["TWEEN_ADMIN_SECRET"] = "x" * 48
    command_id = SecureRandom.uuid
    stub_request(:post, "https://pay.test/internal/admin/v1/resources/wallets/7/commands")
      .with(body: hash_including("operation" => "set_status", "reason" => "Support case 123", "request_id" => command_id))
      .to_return(body: { success: true }.to_json)
    assert_difference('AdminAuditEvent.count', 1) do
      post admin_resource_command_path("wallets", 7), params: {
        operation: "set_status", value: "frozen", reason: "Support case 123", command_id: command_id
      }
    end
    assert_redirected_to admin_resource_record_path("wallets", 7)
    event = AdminAuditEvent.order(:id).last
    assert_equal @staff.matrix_user_id, event.actor_matrix_id
    assert_equal "success", event.outcome
    assert_equal command_id, event.request_id
  ensure
    ENV.delete("TWEEN_PAY_ADMIN_URL")
    ENV.delete("TWEEN_ADMIN_SECRET")
  end

  test "dedicated hostname serves the same dashboard at its root" do
    host! "admin.tween.im"
    post admin_login_path, params: { admin_token: ENV["ADMIN_ACCESS_TOKEN"], matrix_user_id: @staff.matrix_user_id }
    get "/"
    assert_response :success
    assert_select "h1", "Overview"
  end

  test "an expired MFA challenge cannot finish login" do
    @staff.update!(admin_mfa_enabled: true, admin_mfa_secret: ROTP::Base32.random)
    delete admin_logout_path
    post admin_login_path, params: { admin_token: ENV["ADMIN_ACCESS_TOKEN"], matrix_user_id: @staff.matrix_user_id }
    travel_to 11.minutes.from_now do
      post admin_mfa_path, params: { mfa_code: ROTP::TOTP.new(@staff.admin_mfa_secret).now }
      assert_response :unprocessable_entity
      assert_nil session[:admin_user_id]
    end
  end

end
