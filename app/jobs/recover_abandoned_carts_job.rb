# frozen_string_literal: true

class RecoverAbandonedCartsJob < ApplicationJob
  queue_as :default

  def perform
    abandoned_carts.find_each do |cart|
      deliver_abandoned_cart_webhook(cart)
    end
  end

  private

  def abandoned_carts
    ::CommerceCart
      .where(status: "active")
      .where("updated_at < ?", 3.days.ago)
      .where.not(commerce_merchant_id: nil)
  end

  def deliver_abandoned_cart_webhook(cart)
    webhook_url = cart.commerce_merchant.webhook_url
    return unless webhook_url

    event_type = "commerce.cart.abandoned"

    payload = {
      cart_id: cart.cart_id,
      merchant_id: cart.commerce_merchant.merchant_id,
      buyer_user_id: cart.buyer_user_id,
      items: cart.commerce_cart_items.includes(:commerce_sku).map do |item|
        {
          sku_id: item.commerce_sku.sku_id,
          product_id: item.commerce_sku.commerce_product.product_id,
          title: item.commerce_sku.title,
          quantity: item.quantity,
          unit_price_cents: item.unit_price_cents,
          currency: item.currency
        }
      end,
      subtotal_cents: cart.subtotal_cents,
      total_cents: cart.total_cents,
      currency: cart.currency,
      abandoned_at: cart.updated_at.iso8601
    }

    WebhookService.new.deliver(
      event_type: event_type,
      payload: payload,
      webhook_url: webhook_url,
      event_id: "cart_abandoned_#{cart.cart_id}_#{Time.current.to_i}"
    )

    cart.update!(status: "abandoned")
  rescue StandardError => e
    Rails.logger.error "[RecoverAbandonedCartsJob] Failed to notify cart #{cart.cart_id}: #{e.message}"
  end
end
