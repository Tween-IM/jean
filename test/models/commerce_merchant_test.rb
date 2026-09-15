# frozen_string_literal: true

require "test_helper"

class CommerceMerchantTest < ActiveSupport::TestCase
  test "system_merchant creates a platform-owned merchant that is not a person's" do
    merchant = CommerceMerchant.system_merchant

    assert merchant.system_owned?
    assert_equal CommerceMerchant::SYSTEM_MERCHANT_ID, merchant.merchant_id
    assert_equal CommerceMerchant::SYSTEM_MERCHANT_NAME, merchant.display_name
    assert_equal "active", merchant.status
    assert_nil merchant.owner_user_id
    assert merchant.verified?
    assert merchant.wallet_id.present?
  end

  test "system_merchant is idempotent" do
    first = CommerceMerchant.system_merchant
    second = CommerceMerchant.system_merchant

    assert_equal first.id, second.id
    assert_equal 1, CommerceMerchant.system_owned.count
  end

  test "regular merchants are not system owned" do
    merchant = CommerceMerchant.create!(
      miniapp_id: "miniapp.shop.test",
      display_name: "Infinix Mobile",
      status: "active"
    )

    assert_not merchant.system_owned?
    assert_empty CommerceMerchant.system_owned
  end
end
