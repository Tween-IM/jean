# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class ExpirePendingOffersJobTest < ActiveSupport::TestCase
  setup do
    @merchant = CommerceMerchant.create!(
      merchant_id: "mer_offer_expire",
      miniapp_id: "ma_offer_expire",
      display_name: "Offer Expiry Store",
      owner_user_id: "@seller-expire:tween.im",
      wallet_id: "wallet_offer_expire",
      status: "active"
    )
    @conversation = CommerceConversation.create!(
      buyer_user_id: "@buyer-expire:tween.im",
      product_id: "prod_offer_expire",
      status: "open"
    )
  end

  test "expires proposed offers past their deadline" do
    expired = CommerceOffer.create!(
      conversation_id: @conversation.conversation_id,
      proposer_user_id: "@seller-expire:tween.im",
      recipient_user_id: "@buyer-expire:tween.im",
      status: "proposed",
      expires_at: 1.minute.ago,
      total_cents: 100_000
    )
    future = CommerceOffer.create!(
      conversation_id: @conversation.conversation_id,
      proposer_user_id: "@seller-expire:tween.im",
      recipient_user_id: "@buyer-expire:tween.im",
      status: "proposed",
      expires_at: 1.day.from_now,
      total_cents: 100_000
    )

    ExpirePendingOffersJob.new.perform

    assert_equal "expired", expired.reload.status
    assert_equal "proposed", future.reload.status
  end
end
