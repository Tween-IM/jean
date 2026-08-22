# frozen_string_literal: true

require "test_helper"

class CommerceOfferTest < ActiveSupport::TestCase
  setup do
    merchant = CommerceMerchant.create!(
      merchant_id: "mer_offer_test",
      miniapp_id: "ma_offer_test",
      display_name: "Offer Test Store",
      owner_user_id: "@seller-offer:tween.im",
      wallet_id: "wallet_offer_test",
      status: "active"
    )
    @conversation = CommerceConversation.create!(
      buyer_user_id: "@buyer-offer:tween.im",
      product_id: "prod_offer_test",
      status: "open"
    )
    @conversation.update!(matrix_room_id: "!room_offer_test:tween.im")
    @product = merchant.commerce_products.create!(
      product_id: "prod_offer_test",
      title: "Test Product",
      status: "active",
      condition: "new",
      store_type: "marketplace"
    )
  end

  test "proposes an offer with immutable public id and default status" do
    offer = CommerceOffer.create!(
      conversation_id: @conversation.conversation_id,
      proposer_user_id: "@seller-offer:tween.im",
      recipient_user_id: "@buyer-offer:tween.im",
      offer_type: "product",
      subtotal_cents: 100_000,
      delivery_fee_cents: 5_000,
      total_cents: 105_000,
      commission_cents: 5_250,
      seller_proceeds_cents: 99_750,
      expires_at: 24.hours.from_now
    )

    assert_match(/^off_/, offer.offer_id)
    assert_equal 1, offer.version
    assert_equal "draft", offer.status
    assert_equal "NGN", offer.currency
  end

  test "detects expiry" do
    offer = CommerceOffer.new(expires_at: 1.minute.ago)
    assert offer.expired?
  end
end
