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
    assert_select "td", text: /#{Regexp.escape(@staff.matrix_user_id)}/
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

  test "detail drawers render a frame without another application shell" do
    get admin_user_path(@staff), headers: { "Turbo-Frame" => "admin-detail" }
    assert_response :success
    assert_select 'turbo-frame#admin-detail', count: 1
    assert_select '.admin-sidebar', count: 0
  end

  test "official logo and card navigation are present" do
    get admin_dashboard_path
    assert_select 'img[alt="Tween"]'
    assert_select '.admin-page-search a[href=?]', admin_resource_path('cards'), text: /Cards/
  end

  test "document evidence is served privately through the staff boundary" do
    ENV["TWEEN_PAY_ADMIN_URL"] = "https://pay.test"
    ENV["TWEEN_ADMIN_SECRET"] = "x" * 48
    stub_request(:get, "https://pay.test/internal/admin/v1/resources/identity_documents/7/evidence")
      .to_return(body: { content: Base64.strict_encode64("%PDF-test"), content_type: "application/pdf" }.to_json)
    get admin_resource_evidence_path("identity_documents", 7)
    assert_response :success
    assert_equal "%PDF-test", response.body
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    @staff.update!(platform_role: "product_manager")
    get admin_resource_evidence_path("identity_documents", 7)
    assert_response :forbidden
  ensure
    ENV.delete("TWEEN_PAY_ADMIN_URL")
    ENV.delete("TWEEN_ADMIN_SECRET")
  end

  test "savings details show movement context and a controlled reversal form" do
    ENV["TWEEN_PAY_ADMIN_URL"] = "https://pay.test"
    ENV["TWEEN_ADMIN_SECRET"] = "x" * 48
    stub_request(:get, "https://pay.test/internal/admin/v1/resources/pockets/7")
      .to_return(body: { record: { id: 7, title: "School fees", currency: "NGN", balance_cents: 5000, status: "active" },
        savings_transactions: [{ id: 11, direction: "credit", amount_cents: 5000, currency: "NGN", transfer_source: "manual", created_at: Time.current.iso8601, reversed: false }] }.to_json)
    get admin_resource_record_path("pockets", 7)
    assert_response :success
    assert_select "h1", "School fees"
    assert_select 'input[name="arguments[transaction_id]"][value="11"]'
    assert_select 'form[data-turbo-confirm]'
  ensure
    ENV.delete("TWEEN_PAY_ADMIN_URL")
    ENV.delete("TWEEN_ADMIN_SECRET")
  end

  test "compliance review renders private gallery and exact provider details with controlled decisions" do
    ENV["TWEEN_PAY_ADMIN_URL"] = "https://pay.test"
    ENV["TWEEN_ADMIN_SECRET"] = "x" * 48
    stub_request(:get, "https://pay.test/internal/admin/v1/resources/verification_attempts/8")
      .to_return(body: { record: { id: 8, title: "BVN · Validate", customer_name: "Synthetic Customer", status: "failed", review_status: "pending", approval_blocked_reason: nil } }.to_json)
    stub_request(:get, "https://pay.test/internal/admin/v1/resources/verification_attempts/8/evidence")
      .to_return(body: { details: { provider_calls: [{ http_status: 400, raw_body: { message: "Provider unavailable" } }] }, images: [{ index: 0, label: "Provider identity photo" }], evidence_digest: "review-version" }.to_json)
    get admin_resource_record_path("verification_attempts", 8)
    assert_response :success
    assert_select "h2", "Retained evidence"
    assert_select 'img[alt="Provider identity photo"]'
    assert_select 'input[name="arguments[evidence_digest]"][value="review-version"]'
    assert_select 'input[name="arguments[acknowledged]"][required]'
    assert_select 'section[data-turbo-temporary]'
    assert_includes response.body, "Provider unavailable"
    assert_includes response.headers["Cache-Control"], "no-store"
  ensure
    ENV.delete("TWEEN_PAY_ADMIN_URL")
    ENV.delete("TWEEN_ADMIN_SECRET")
  end

  test "duplicate customer directories route back to People" do
    get admin_resource_path('payment_accounts')
    assert_redirected_to admin_users_path
    get admin_resource_path('verifications')
    assert_redirected_to admin_users_path
  end

  test "navigation has stable areas and a single current secondary navigation" do
    get admin_users_path
    assert_select '.admin-primary-navigation .admin-area-link', count: 8
    assert_select '.admin-primary-navigation a[aria-current=true]', text: 'People'
    assert_select 'details.admin-nav-group', count: 0
    assert_select '.admin-secondary-navigation', count: 1
    assert_select '.admin-primary-navigation a', text: 'Trust & safety'
  end

  test "canonical person profile receives legacy payment account links" do
    ENV['TWEEN_PAY_ADMIN_URL'] = 'https://pay.test'
    ENV['TWEEN_ADMIN_SECRET'] = 'x' * 48
    stub_request(:get, 'https://pay.test/internal/admin/v1/resources/payment_accounts/17')
      .to_return(body: { record: { id: 17, customer_matrix_id: @staff.matrix_user_id, status: 'active' } }.to_json)
    get admin_resource_record_path('payment_accounts', 17)
    assert_redirected_to admin_user_path(@staff, tab: 'payments')
  ensure
    ENV.delete('TWEEN_PAY_ADMIN_URL')
    ENV.delete('TWEEN_ADMIN_SECRET')
  end

end
