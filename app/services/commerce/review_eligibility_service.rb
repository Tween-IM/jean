# frozen_string_literal: true

module Commerce
  class ReviewEligibilityService
    def self.can_review?(buyer_user_id:, product:)
      # Must have a completed order for this product's merchant
      has_completed_order = ::CommerceOrder.exists?(
        buyer_user_id: buyer_user_id,
        commerce_merchant: product.commerce_merchant,
        status: %w[paid processing fulfilled]
      )

      return { eligible: false, reason: "No completed purchase found" } unless has_completed_order

      # Must not have already reviewed this product
      existing_review = ::CommerceReview.exists?(
        buyer_user_id: buyer_user_id,
        commerce_product: product
      )

      if existing_review
        return { eligible: false, reason: "You have already reviewed this product" }
      end

      { eligible: true }
    end
  end
end
