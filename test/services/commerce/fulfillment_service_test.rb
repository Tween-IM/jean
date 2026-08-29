# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class Commerce::FulfillmentServiceTest < ActiveSupport::TestCase
  setup do
    @merchant = CommerceMerchant.create!(
      merchant_id: "mer_ful_service",
      miniapp_id: "ma_ful_service",
      display_name: "Fulfilment Service Store",
      owner_user_id: "@seller-ful:tween.im",
      wallet_id: "wallet_ful_service",
      status: "active"
    )
    @order = CommerceOrder.create!(
      commerce_merchant: @merchant,
      buyer_user_id: "@buyer-ful:tween.im",
      payment_id: "pay_ful_service",
      currency: "NGN",
      status: "paid",
      protection_status: "active",
      protected_payment_id: "ppay_ful_service"
    )
  end

  test "seller creates a shipment with tracking" do
    service = Commerce::FulfillmentService.new
    fulfillment = service.create_shipment!(
      @order,
      "@seller-ful:tween.im",
      carrier: "GIG", tracking_number: "GIG-123", tracking_url: "https://track.example/123"
    )

    assert_equal "shipped", fulfillment.status
    assert_equal "GIG-123", fulfillment.tracking_number
    assert_equal "partially_fulfilled", @order.reload.fulfillment_status
  end

  test "buyer confirming delivery triggers immediate release" do
    service = Commerce::FulfillmentService.new
    fulfillment = service.create_shipment!(@order, "@seller-ful:tween.im", tracking_number: "GIG-456")
    fulfillment.update!(status: "delivered", delivered_at: Time.current)

    ProtectedCommerceService.stub(:schedule_release, stub_release) do
      result = service.confirm_delivery!(@order, "@buyer-ful:tween.im")

      assert_equal "accepted", fulfillment.reload.status
      assert_equal "fulfilled", @order.reload.status
      assert_not_nil result[:inspection_deadline]
    end
  end

  test "seller submits service completion evidence" do
    service = Commerce::FulfillmentService.new
    fulfillment = service.begin_service!(@order, "@seller-ful:tween.im")
    fulfillment.update!(status: "in_progress")

    submitted = service.submit_service!(
      @order,
      "@seller-ful:tween.im",
      evidence: [ { media_type: "image", url: "https://cdn.example/photo.jpg" } ]
    )

    assert_equal "submitted", submitted.status
    assert_equal 1, submitted.events.where(event_type: "service.submitted").count
  end

  test "only the buyer can confirm delivery" do
    service = Commerce::FulfillmentService.new
    fulfillment = service.create_shipment!(@order, "@seller-ful:tween.im")
    fulfillment.update!(status: "delivered")

    assert_raises(Commerce::FulfillmentService::NotAuthorizedError) do
      service.confirm_delivery!(@order, "@seller-ful:tween.im")
    end
  end

  test "pickup handover uses a one-time hashed code" do
    service = Commerce::FulfillmentService.new
    service.ready_for_pickup!(@order, "@seller-ful:tween.im")

    code = service.issue_pickup_code!(@order, "@buyer-ful:tween.im")
    assert_match(/\A[A-Z0-9]{6}\z/, code)

    pickup_code = CommercePickupCode.last
    assert_not_equal code, pickup_code.code_hash
    assert_equal Digest::SHA256.hexdigest(code), pickup_code.code_hash

    ProtectedCommerceService.stub(:schedule_release, stub_release) do
      fulfillment = service.confirm_pickup!(@order, "@seller-ful:tween.im", code)
      assert_equal "handed_over", fulfillment.status
    end
    assert_equal "used", pickup_code.reload.status
  end

  test "pickup code is rejected when it does not match" do
    service = Commerce::FulfillmentService.new
    service.ready_for_pickup!(@order, "@seller-ful:tween.im")
    service.issue_pickup_code!(@order, "@buyer-ful:tween.im")

    assert_raises(CommercePickupCode::InvalidCodeError) do
      service.confirm_pickup!(@order, "@seller-ful:tween.im", "WRONG")
    end
  end

  test "milestones release their own amount via partial release" do
    service = Commerce::FulfillmentService.new
    service_order = CommerceOrder.create!(
      commerce_merchant: @merchant,
      buyer_user_id: "@buyer-ful:tween.im",
      payment_id: "pay_ful_service_2",
      currency: "NGN",
      status: "paid",
      source: "service_booking",
      fulfillment_type: "service",
      protection_status: "active",
      protected_payment_id: "ppay_ful_service_2"
    )
    service.begin_service!(service_order, "@seller-ful:tween.im")

    milestone = service.add_milestone!(service_order, "@seller-ful:tween.im",
                                       title: "Design", amount_cents: 40_000)
    service.submit_milestone!(service_order, "@seller-ful:tween.im", milestone,
                              evidence: [ { media_type: "image", url: "https://cdn.example/d.png" } ])

    ProtectedCommerceService.stub(:release, stub_release) do
      accepted = service.accept_milestone!(service_order, "@buyer-ful:tween.im", milestone)
      assert_equal "released", accepted.reload.status
      assert accepted.released_at.present?
    end
  end

  private

  def stub_release
    { protected_payment: { protected_payment_id: "ppay_ful_service", status: "released" } }
  end
end
