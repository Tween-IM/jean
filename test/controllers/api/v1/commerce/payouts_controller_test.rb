require "test_helper"

class Api::V1::Commerce::PayoutsControllerTest < ActionDispatch::IntegrationTest
  test "merchant can list payouts" do
    owner = create_user("payout_owner")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "ma.payout.test", display_name: "Payout Shop", status: "active")
    merchant.commerce_payouts.create!(amount_cents: 5000, currency: "NGN", status: "completed")
    merchant.commerce_payouts.create!(amount_cents: 3000, currency: "NGN", status: "pending")

    get api_v1_commerce_payouts_url,
      headers: tep_headers(owner, "commerce:merchant"),
      as: :json

    assert_response :success
    assert_equal 2, response.parsed_body["payouts"].size
    assert_equal 2, response.parsed_body["meta"]["total"]
  end

  test "merchant can create payout" do
    owner = create_user("payout_create_owner")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "ma.payoutcreate.test", display_name: "Payout Create Shop", status: "active")

    with_wallet_stub(:get_balance, { balance: { available: 100.0, currency: "NGN" } }) do
      with_wallet_stub(:initiate_payout, { "reference" => "PO123", "status" => "processing" }) do
        post api_v1_commerce_payouts_url,
          params: { payout: { amount_cents: 5000, currency: "NGN", payout_method: "bank_transfer", destination_account_number: "1234567890", destination_bank_code: "011", destination_bank_name: "First Bank" } },
          headers: tep_headers(owner, "commerce:merchant"),
          as: :json
      end
    end

    assert_response :created
    assert_equal "processing", response.parsed_body.dig("payout", "status")
    assert_equal 5000, response.parsed_body.dig("payout", "amount_cents")
    assert_equal "******7890", response.parsed_body.dig("payout", "destination", "account_number")
  end

  test "payout fails with insufficient balance" do
    owner = create_user("payout_insufficient_owner")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "ma.payoutins.test", display_name: "Payout Insufficient Shop", status: "active")

    with_wallet_stub(:get_balance, { balance: { available: 10.0, currency: "NGN" } }) do
      post api_v1_commerce_payouts_url,
        params: { payout: { amount_cents: 5000, currency: "NGN", payout_method: "bank_transfer", destination_account_number: "1234567890" } },
        headers: tep_headers(owner, "commerce:merchant"),
        as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "insufficient_balance", response.parsed_body["error"]
  end

  test "non-merchant cannot create payout" do
    owner = create_user("payout_forbidden_owner")
    other = create_user("other_user")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "ma.payoutforb.test", display_name: "Payout Forbidden Shop", status: "active")

    post api_v1_commerce_payouts_url,
      params: { payout: { amount_cents: 1000, currency: "NGN" } },
      headers: tep_headers(other, "commerce:merchant"),
      as: :json

    assert_response :not_found
  end

  test "invalid amount returns error" do
    owner = create_user("payout_invalid_owner")
    merchant = CommerceMerchant.create!(owner_user_id: owner.matrix_user_id, miniapp_id: "ma.payoutinv.test", display_name: "Payout Invalid Shop", status: "active")

    post api_v1_commerce_payouts_url,
      params: { payout: { amount_cents: 0, currency: "NGN" } },
      headers: tep_headers(owner, "commerce:merchant"),
      as: :json

    assert_response :bad_request
    assert_equal "invalid_amount", response.parsed_body["error"]
  end

  private

  def create_user(username)
    User.create!(matrix_user_id: "@#{username}:example.com", matrix_username: "#{username}:example.com", matrix_homeserver: "example.com")
  end

  def tep_headers(user, scopes)
    token = TepTokenService.encode({ user_id: user.matrix_user_id, miniapp_id: "miniapp.commerce.test" }, scopes: scopes.split)
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
