# frozen_string_literal: true

# Release timeout: a shipped/pickup order whose inspection window has elapsed
# with no dispute is auto-released, so release never depends on the buyer
# alone. Idempotent — already-confirmed or disputed orders are skipped.
class AutoReleaseDeliveredOrdersJob < ApplicationJob
  queue_as :default

  INSPECTION_HOURS = 24

  def perform
    cutoff = Time.current - INSPECTION_HOURS.hours

    CommerceFulfillment.where(status: %w[delivered handed_over submitted])
                       .where('delivered_at <= ?', cutoff)
                       .find_each(batch_size: 100) do |fulfillment|
      order = fulfillment.commerce_order
      next unless eligible?(order)

      begin
        fulfillment.update!(status: "accepted", accepted_at: Time.current)
        order.update!(status: "processing",
                      metadata: order.metadata.merge("inspection_timeout" => true))
        ProtectedCommerceService.schedule_release(
          order.protected_payment_id,
          release_at: Time.current.iso8601
        )
        CommerceNotifier.payment_releasing(order)
      rescue ProtectedCommerceService::Error => e
        Rails.logger.error "[AutoReleaseDelivered] release failed for #{order.order_id}: #{e.message}"
      end
    end
  end

  private

  def eligible?(order)
    order.status == "paid" &&
      order.protection_status == "active" &&
      order.protected_payment_id.present? &&
      !order.commerce_disputes.where(status: %w[open under_review]).exists?
  end
end
