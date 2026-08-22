# frozen_string_literal: true

# Seller no-show / missed fulfilment deadline auto-cancellation.
#
# A protected order that is funded (paid, protection active) but whose seller
# has not started fulfilment within the fulfilment window is auto-refunded.
# The refund is issued through Tween Pay so the money actually moves back to
# the buyer's wallet, then the order is marked refunded.
class AutoCancelStaleOrdersJob < ApplicationJob
  queue_as :default

  FULFILLMENT_WINDOW_HOURS = 48

  def perform
    cutoff = Time.current - FULFILLMENT_WINDOW_HOURS.hours

    CommerceOrder.where(status: "paid", protection_status: "active")
                 .where("created_at <= ?", cutoff)
                 .find_each do |order|
      next if seller_started?(order)

      cancel_no_show!(order)
    end
  end

  private

  def seller_started?(order)
    fulfillment = order.commerce_fulfillments.latest_first.first
    return false unless fulfillment

    case order.fulfillment_type
    when "service"
      fulfillment.status.in?(%w[in_progress submitted inspection accepted])
    else
      fulfillment.status.in?(%w[shipped delivered accepted handed_over])
    end
  end

  def cancel_no_show!(order)
    Rails.logger.info "[AutoCancelStaleOrders] no-show refund for order #{order.order_id}"

    unless order.protected_payment_id.present?
      order.update!(status: "cancelled", fulfillment_status: "not_required",
                    metadata: order.metadata.merge("cancelled_reason" => "seller_no_show"))
      return
    end

    ProtectedCommerceService.refund(
      order.protected_payment_id,
      amount_cents: order.total_cents,
      reason: "seller_no_show",
      actor: "auto_cancel_worker"
    )
    order.update!(status: "refunded", protection_status: "completed",
                  metadata: order.metadata.merge("cancelled_reason" => "seller_no_show",
                                                 "auto_refunded_at" => Time.current.iso8601))
  rescue ProtectedCommerceService::Error => e
    Rails.logger.error "[AutoCancelStaleOrders] refund failed for #{order.order_id}: #{e.message}"
  end
end
