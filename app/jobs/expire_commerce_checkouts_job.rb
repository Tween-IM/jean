# frozen_string_literal: true
class ExpireCommerceCheckoutsJob < ApplicationJob
  queue_as :default

  def perform
    CommerceCheckout
      .where(status: "payment_pending")
      .where("expires_at <= ?", Time.current)
      .find_each { |checkout| expire_checkout(checkout) }
  end

  private

  def expire_checkout(checkout)
    order = CommerceOrder.find_by(order_id: checkout.order_id)
    CommerceCheckout.transaction do
      ::Commerce::InventoryService.restore!(order) if order
      checkout.update!(status: "expired", metadata: checkout.metadata.merge("expired_at" => Time.current.iso8601))
      order&.update!(status: "cancelled", metadata: order.metadata.merge("inventory_restored" => true, "cancelled_reason" => "checkout_expired"))
      checkout.commerce_cart.update!(status: "abandoned")
    end
  end


end
