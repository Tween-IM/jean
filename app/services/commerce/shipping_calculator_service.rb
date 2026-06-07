# frozen_string_literal: true

module Commerce
  class ShippingCalculatorService
    def self.calculate_for_cart(cart:, destination_country:, destination_state: nil)
      merchant = cart.commerce_merchant
      profiles = merchant.commerce_shipping_profiles.active

      results = []
      total_shipping_cents = 0

      # Get total weight of cart items
      total_weight = cart.commerce_cart_items.joins(commerce_sku: :commerce_product).sum("COALESCE(commerce_products.weight_grams, 0)")

      profiles.each do |profile|
        result = profile.calculate_shipping(
          destination_country: destination_country,
          destination_state: destination_state,
          weight_grams: total_weight.positive? ? total_weight : nil,
          subtotal_cents: cart.subtotal_cents
        )
        results << result.merge(profile_id: profile.shipping_profile_id)
        total_shipping_cents = result[:rate_cents] if result[:rate_cents].present? && total_shipping_cents.zero?
      end

      {
        options: results,
        total_shipping_cents: total_shipping_cents
      }
    end

    def self.calculate_for_product(product:, destination_country:, destination_state: nil, quantity: 1)
      profiles = product.commerce_shipping_profiles.active

      weight = product.weight_grams.to_i * quantity

      profiles.map do |profile|
        profile.calculate_shipping(
          destination_country: destination_country,
          destination_state: destination_state,
          weight_grams: weight.positive? ? weight : nil
        ).merge(profile_id: profile.shipping_profile_id)
      end
    end
  end
end
