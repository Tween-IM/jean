# frozen_string_literal: true

require "test_helper"

class CommerceOrderTest < ActiveSupport::TestCase
  test "valid status transitions" do
    merchant = CommerceMerchant.create!(owner_user_id: "@owner:example.com", miniapp_id: "ma.test", display_name: "Test", status: "active")
    order = CommerceOrder.create!(
      commerce_merchant: merchant,
      buyer_user_id: "@buyer:example.com",
      payment_id: "pay_test",
      status: "pending_payment",
      total_cents: 1000,
      currency: "NGN"
    )

    # pending_payment -> paid
    order.update!(status: "paid")
    assert_equal "paid", order.status

    # paid -> refunded
    order.update!(status: "refunded")
    assert_equal "refunded", order.status
  end

  test "invalid status transition is blocked" do
    merchant = CommerceMerchant.create!(owner_user_id: "@owner:example.com", miniapp_id: "ma.test2", display_name: "Test2", status: "active")
    order = CommerceOrder.create!(
      commerce_merchant: merchant,
      buyer_user_id: "@buyer:example.com",
      payment_id: "pay_test2",
      status: "refunded",
      total_cents: 1000,
      currency: "NGN"
    )

    assert_raises(ActiveRecord::RecordNotSaved) do
      order.update!(status: "paid")
    end
  end

  test "cancelled order cannot transition" do
    merchant = CommerceMerchant.create!(owner_user_id: "@owner:example.com", miniapp_id: "ma.test3", display_name: "Test3", status: "active")
    order = CommerceOrder.create!(
      commerce_merchant: merchant,
      buyer_user_id: "@buyer:example.com",
      payment_id: "pay_test3",
      status: "cancelled",
      total_cents: 1000,
      currency: "NGN"
    )

    assert_raises(ActiveRecord::RecordNotSaved) do
      order.update!(status: "paid")
    end
  end

  test "same status update is allowed" do
    merchant = CommerceMerchant.create!(owner_user_id: "@owner:example.com", miniapp_id: "ma.test4", display_name: "Test4", status: "active")
    order = CommerceOrder.create!(
      commerce_merchant: merchant,
      buyer_user_id: "@buyer:example.com",
      payment_id: "pay_test4",
      status: "paid",
      total_cents: 1000,
      currency: "NGN"
    )

    # Should not raise
    order.update!(status: "paid")
    assert_equal "paid", order.status
  end
end
