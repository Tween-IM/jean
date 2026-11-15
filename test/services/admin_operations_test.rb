require "test_helper"

class AdminOperationsTest < ActiveSupport::TestCase
  test "money inputs preserve cents and reject truncation or exponent notation" do
    assert_equal 12345, Admin::Operations.cents("123.45")
    assert_equal 10, Admin::Operations.cents("0.10")
    %w[-1 1.001 1e6 NaN Infinity].each do |input|
      assert_raises(ArgumentError) { Admin::Operations.cents(input) }
    end
  end

  test "only explicit operation arguments cross the staff service boundary" do
    params = ActionController::Parameters.new(arguments: { amount: "12.34", actor: "someone_else", balance: "999999" })
    assert_equal({ "amount_cents" => 1234 }, JSON.parse(Admin::Operations.arguments("refund_balance", params)))
    params = ActionController::Parameters.new(arguments: { price: { program_id: "program", price_id: "quote", charge_cents: 500, charge_currency: "NGN", identity: "injected" }.to_json })
    refute JSON.parse(Admin::Operations.arguments("issue_card", params)).key?("identity")
  end

  test "uncertain provider results keep a distinct retry outcome" do
    client = Admin::RemoteClient.new(url: "https://service.test", token: "test")
    stub_request(:post, "https://service.test/command").to_return(status: 422, body: { state: "unknown" }.to_json)
    assert_raises(Admin::RemoteClient::OutcomeUnknown) { client.request(:post, "/command", body: {}) }
    stub_request(:post, "https://service.test/command").to_return(status: 422, body: { state: "rejected" }.to_json)
    assert_raises(Admin::RemoteClient::Rejected) { client.request(:post, "/command", body: {}) }
  end

  test "local resource client keeps missing records within the public error contract" do
    actor = User.new(platform_role: "super_admin")
    client = Admin::LocalResourceClient.new(Admin::Resources::CATALOG.fetch("disputes"), actor: actor)
    assert_raises(Admin::RemoteClient::NotFound) { client.detail("disputes", -1) }
  end
  test "dispute rejection permits a corrected decision while uncertainty keeps its original key" do
    actor = User.create!(matrix_user_id: "@case-staff:tween.im", matrix_username: "case-staff:tween.im", matrix_homeserver: "tween.im", platform_role: "super_admin")
    merchant = CommerceMerchant.create!(merchant_id: "mer_staff_case", miniapp_id: "ma_case", display_name: "Case store", owner_user_id: "@seller:tween.im", wallet_id: "case_wallet", status: "active")
    order = CommerceOrder.create!(commerce_merchant: merchant, buyer_user_id: "@buyer:tween.im", currency: "NGN", payment_id: "pay_staff_case", total_cents: 1000, status: "paid")
    dispute = order.commerce_disputes.create!(opened_by_user_id: "@buyer:tween.im", reason: "item_not_received", status: "open", protected_payment_id: "ppay_case")
    client = Admin::LocalResourceClient.new(Admin::Resources::CATALOG.fetch("disputes"), actor: actor)
    ENV["TWEEN_PAY_ADMIN_URL"] = "https://pay.test"
    ENV["TWEEN_ADMIN_SECRET"] = "x" * 48
    endpoint = "https://pay.test/internal/admin/v1/resources/protected_payments/ppay_case/commands"
    value = { outcome: "resolved_buyer", seller_amount_cents: 0, buyer_refund_cents: 1000 }.to_json
    stub_request(:post, endpoint).to_return(status: 422, body: '{}')
    assert_raises(Admin::RemoteClient::Rejected) { client.resolve_dispute(dispute, "Review case", SecureRandom.uuid, value) }
    assert_nil dispute.reload.resolution["command_id"]
    key = SecureRandom.uuid
    stub_request(:post, endpoint).to_return(status: 503)
    assert_raises(Admin::RemoteClient::Unavailable) { client.resolve_dispute(dispute, "Review case", key, value) }
    assert_equal key, dispute.reload.resolution["command_id"]
    assert_equal "unknown", dispute.resolution["phase"]
    assert_raises(Admin::RemoteClient::Rejected) { client.resolve_dispute(dispute, "Changed decision", SecureRandom.uuid, value) }
    stub_request(:post, endpoint).to_return(body: { success: true }.to_json)
    client.resolve_dispute(dispute, "Review case", key, value)
    assert_equal "resolved", dispute.reload.status
  ensure
    ENV.delete("TWEEN_PAY_ADMIN_URL")
    ENV.delete("TWEEN_ADMIN_SECRET")
  end

end
