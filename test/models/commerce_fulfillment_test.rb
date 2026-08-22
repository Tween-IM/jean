# frozen_string_literal: true

require "test_helper"

class CommerceFulfillmentTest < ActiveSupport::TestCase
  setup do
    merchant = CommerceMerchant.create!(
      merchant_id: "mer_fulfillment_test",
      miniapp_id: "ma_fulfillment_test",
      display_name: "Fulfillment Test Store",
      owner_user_id: "@seller:tween.im",
      wallet_id: "wallet_fulfillment_test",
      status: "active"
    )
    @order = CommerceOrder.create!(
      commerce_merchant: merchant,
      buyer_user_id: "@buyer:tween.im",
      payment_id: "pay_fulfillment_test",
      currency: "NGN"
    )
  end

  test "shipment follows the delivery state machine" do
    fulfillment = @order.commerce_fulfillments.create!(kind: "shipment")

    assert fulfillment.update(status: "preparing")
    assert fulfillment.update(status: "shipped", shipped_at: Time.current)
    assert fulfillment.update(status: "delivered", delivered_at: Time.current)
    assert fulfillment.update(status: "accepted", accepted_at: Time.current)
  end

  test "shipment rejects an impossible transition" do
    fulfillment = @order.commerce_fulfillments.create!(kind: "shipment")

    assert_not fulfillment.update(status: "accepted")
    assert_includes fulfillment.errors[:status], "cannot transition from unfulfilled to accepted"
  end

  test "service uses service-specific statuses" do
    fulfillment = @order.commerce_fulfillments.create!(
      kind: "service",
      status: "scheduled"
    )

    assert fulfillment.update(status: "in_progress")
    assert fulfillment.update(status: "submitted")
    assert fulfillment.update(status: "inspection")
    assert fulfillment.update(status: "accepted")
  end

  test "events receive immutable public identifiers and timestamps" do
    fulfillment = @order.commerce_fulfillments.create!(kind: "shipment")
    event = fulfillment.events.create!(event_type: "shipment.preparing")

    assert_match(/^fev_/, event.event_id)
    assert event.occurred_at.present?
    assert_not event.update(event_type: "shipment.delivered")
    assert_not event.destroy
  end
end
