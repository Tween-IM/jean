# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class AutoCancelStaleOrdersJobTest < ActiveSupport::TestCase
  setup do
    @merchant = CommerceMerchant.create!(
      merchant_id: "mer_no_show",
      miniapp_id: "ma_no_show",
      display_name: "No Show Store",
      owner_user_id: "@seller-noshow:tween.im",
      wallet_id: "wallet_no_show",
      status: "active"
    )
    @order = CommerceOrder.create!(
      commerce_merchant: @merchant,
      buyer_user_id: "@buyer-noshow:tween.im",
      payment_id: "pay_no_show",
      currency: "NGN",
      status: "paid",
      protection_status: "active",
      protected_payment_id: "ppay_no_show",
      total_cents: 50_000,
      created_at: 3.days.ago
    )
  end

  test "auto-refunds a funded order whose seller never started fulfilment" do
    ProtectedCommerceService.stub(:refund, { protected_payment: { status: "refunded" } }) do
      AutoCancelStaleOrdersJob.new.perform
    end

    assert_equal "refunded", @order.reload.status
    assert_equal "completed", @order.reload.protection_status
    assert_equal "seller_no_show", @order.reload.metadata["cancelled_reason"]
  end

  test "leaves orders where the seller has shipped alone" do
    @order.commerce_fulfillments.create!(kind: "shipment", status: "shipped",
                                         shipped_at: 1.day.ago)

    ProtectedCommerceService.stub(:refund, { protected_payment: { status: "refunded" } }) do
      AutoCancelStaleOrdersJob.new.perform
    end

    assert_equal "paid", @order.reload.status
  end
end
