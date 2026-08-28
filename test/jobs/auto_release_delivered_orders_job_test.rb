# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class AutoReleaseDeliveredOrdersJobTest < ActiveSupport::TestCase
  setup do
    @merchant = CommerceMerchant.create!(
      merchant_id: "mer_auto_rel",
      miniapp_id: "ma_auto_rel",
      display_name: "Auto Rel Store",
      owner_user_id: "@seller-autorel:tween.im",
      wallet_id: "wallet_auto_rel",
      status: "active"
    )
    @order = CommerceOrder.create!(
      commerce_merchant: @merchant,
      buyer_user_id: "@buyer-autorel:tween.im",
      payment_id: "pay_auto_rel",
      currency: "NGN",
      status: "paid",
      protection_status: "active",
      protected_payment_id: "ppay_auto_rel",
      total_cents: 50_000
    )
  end

  test "auto-releases a delivered order after the inspection window with no dispute" do
    fulfillment = @order.commerce_fulfillments.create!(
      kind: "shipment", status: "delivered", delivered_at: 25.hours.ago
    )

    ProtectedCommerceService.stub(:schedule_release, { protected_payment: { status: "release_scheduled" } }) do
      AutoReleaseDeliveredOrdersJob.new.perform
    end

    assert_equal "accepted", fulfillment.reload.status
    assert_equal "processing", @order.reload.status
    assert_equal true, @order.reload.metadata["inspection_timeout"]
  end

  test "skips delivered orders with an open dispute" do
    fulfillment = @order.commerce_fulfillments.create!(
      kind: "shipment", status: "delivered", delivered_at: 25.hours.ago
    )
    @order.commerce_disputes.create!(opened_by_user_id: "@seller-autorel:tween.im", reason: "item_not_received", status: "open")

    ProtectedCommerceService.stub(:schedule_release, { protected_payment: { status: "release_scheduled" } }) do
      AutoReleaseDeliveredOrdersJob.new.perform
    end

    assert_equal "delivered", fulfillment.reload.status
    assert_equal "paid", @order.reload.status
  end
end
