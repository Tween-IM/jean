# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class Commerce::OfferServiceTest < ActiveSupport::TestCase
  setup do
    @merchant = CommerceMerchant.create!(
      merchant_id: "mer_offer_service",
      miniapp_id: "ma_offer_service",
      display_name: "Offer Service Store",
      owner_user_id: "@seller-service:tween.im",
      wallet_id: "wallet_offer_service",
      status: "active"
    )
    @conversation = CommerceConversation.create!(
      buyer_user_id: "@buyer-service:tween.im",
      product_id: "prod_offer_service",
      status: "open"
    )
    @merchant.commerce_products.create!(
      product_id: "prod_offer_service",
      title: "Service Product",
      status: "active",
      condition: "new",
      store_type: "marketplace"
    )
  end

  def offer_params
    {
      offer_type: "product",
      subtotal_cents: 100_000,
      delivery_fee_cents: 5_000,
      total_cents: 105_000,
      commission_cents: 5_250,
      seller_proceeds_cents: 99_750,
      terms: { product_id: "prod_offer_service", quantity: 1, delivery_method: "shipment" }
    }
  end

  test "proposes an offer" do
    service = Commerce::OfferService.new
    offer = service.create!(@conversation, "@seller-service:tween.im", offer_params)

    assert_equal "proposed", offer.status
    assert_equal "@buyer-service:tween.im", offer.recipient_user_id
    assert_equal "NGN", offer.currency
  end

  test "rejects non-participants" do
    service = Commerce::OfferService.new
    assert_raises(Commerce::OfferService::NotParticipantError) do
      service.create!(@conversation, "@stranger:tween.im", offer_params)
    end
  end

  test "counteroffer supersedes the previous version" do
    service = Commerce::OfferService.new
    first = service.create!(@conversation, "@seller-service:tween.im", offer_params)

    counter = service.counter!(
      first,
      "@buyer-service:tween.im",
      offer_params.merge(subtotal_cents: 90_000, total_cents: 95_000, commission_cents: 4_750)
    )

    assert_equal 2, counter.version
    assert_equal "@buyer-service:tween.im", counter.proposer_user_id
    assert_equal "superseded", first.reload.status
    assert_equal counter.offer_id, first.reload.superseded_by_offer_id
    assert_equal first.offer_id, counter.parent_offer_id
  end

  test "acceptance creates a protected order and requests a protected payment" do
    service = Commerce::OfferService.new
    offer = service.create!(@conversation, "@seller-service:tween.im", offer_params)

    ProtectedCommerceService.stub(:create_payment, stub_payment_response) do
      order = service.accept!(offer, "@buyer-service:tween.im")

      assert_equal "accepted", offer.reload.status
      assert_equal "@buyer-service:tween.im", offer.reload.accepted_by_user_id
      assert_equal "conversation", order.source
      assert_equal "active", order.reload.protection_status
      assert_equal offer.offer_id, order.accepted_offer_id
      assert_equal 105_000, order.total_cents
      assert order.protected_payment_id.present?
      assert_equal 1, order.commerce_order_items.count
    end
  end

  test "acceptance is refused after expiry" do
    service = Commerce::OfferService.new
    offer = service.create!(@conversation, "@seller-service:tween.im", offer_params)
    offer.update!(expires_at: 1.minute.ago)

    assert_raises(Commerce::OfferService::ExpiredError) do
      service.accept!(offer, "@buyer-service:tween.im")
    end
  end

  test "acceptance requires the recipient" do
    service = Commerce::OfferService.new
    offer = service.create!(@conversation, "@seller-service:tween.im", offer_params)

    assert_raises(Commerce::OfferService::NotRecipientError) do
      service.accept!(offer, "@seller-service:tween.im")
    end
  end

  private

  def stub_payment_response
    { protected_payment: {
        protected_payment_id: "ppay_test_123",
        order_id: "ord_test",
        status: "payment_pending"
      } }
  end
end
