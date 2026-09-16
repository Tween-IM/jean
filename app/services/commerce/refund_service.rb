# frozen_string_literal: true

module Commerce
  # Refunds an order: moves the money, restores inventory on a full refund,
  # records the refund on the order and tells the buyer.
  #
  # Two channels exist, and they are not interchangeable:
  #
  #   * `:protected` — the protected-payment ledger in Tween Pay. jean
  #     authenticates with its internal token, which is why platform staff can
  #     refund these (every mirrored catalogue order is one of these).
  #   * `:wallet` — the legacy wallet payment. Tween Pay authorises this
  #     against the *merchant's* wallet, so it needs that merchant's own TEP
  #     token; the admin surface can therefore only report it, not perform it.
  #
  # An order with no channel is refused rather than marked refunded: quoting a
  # refund that moved no money is worse than an honest error.
  class RefundService
    class Error < StandardError; end
    class UnsupportedError < Error; end

    Result = Struct.new(:order, :amount_cents, :full_refund, :channel, keyword_init: true)

    def initialize(tep_token: nil)
      @tep_token = tep_token
    end

    def call(order:, amount_cents:, reason: "merchant_refund", actor: nil, metadata: {})
      amount_cents = amount_cents.to_i
      raise Error, "Refund amount must be greater than zero" unless amount_cents.positive?
      raise Error, "Refund cannot exceed the order total (#{order.total_cents} #{order.currency})" if amount_cents > order.total_cents

      full_refund = amount_cents >= order.total_cents
      channel = channel_for(order)

      case channel
      when :protected
        refund_protected!(order, amount_cents, reason, actor)
      when :wallet
        refund_wallet!(order, amount_cents, reason)
      else
        raise UnsupportedError,
          "This order has no refundable payment channel yet. " \
          "Protected orders refund here; legacy wallet payments must be refunded by the merchant."
      end

      record_refund!(order, amount_cents: amount_cents, reason: reason, actor: actor,
        metadata: metadata, full_refund: full_refund)
      notify_buyer!(order, amount_cents: amount_cents, reason: reason)

      Result.new(order: order.reload, amount_cents: amount_cents, full_refund: full_refund, channel: channel)
    end

    private

    def channel_for(order)
      return :protected if order.protected_payment_id.present?
      return :wallet if order.payment_id.present? && order.status == "paid"

      nil
    end

    def refund_protected!(order, amount_cents, reason, actor)
      ProtectedCommerceService.refund(
        order.protected_payment_id,
        amount_cents: amount_cents,
        reason: reason,
        actor: actor.presence || "jean_admin"
      )
    rescue ProtectedCommerceService::Error => e
      Rails.logger.error "[RefundService] protected refund failed for #{order.order_id}: #{e.message}"
      raise Error, "Tween Pay refused the refund: #{e.message}"
    end

    def refund_wallet!(order, amount_cents, reason)
      response = WalletService.refund_payment(
        order.payment_id,
        amount_cents / 100.0,
        order.currency,
        reason,
        @tep_token
      )

      refund_reference = response.is_a?(Hash) &&
        (response["refund_id"] || response[:refund_id] || response["id"] || response[:id])
      return if refund_reference

      Rails.logger.warn "[RefundService] wallet refund refused for #{order.order_id}: #{response.inspect}"
      raise Error, "The wallet could not process this refund. Please try again."
    rescue WalletService::WalletError => e
      Rails.logger.error "[RefundService] wallet refund error for #{order.order_id}: #{e.message}"
      raise Error, "The wallet could not process this refund: #{e.message}"
    end

    def record_refund!(order, amount_cents:, reason:, actor:, metadata:, full_refund:)
      if full_refund
        ::Commerce::InventoryService.restore!(order)
        order.metadata = order.metadata.merge("inventory_restored" => true, "cancelled_reason" => "refunded")
      end

      entry = {
        "amount_cents" => amount_cents,
        "reason" => reason,
        "created_at" => Time.current.iso8601,
        "processed_by" => actor.presence || "system"
      }.merge(metadata.to_h.transform_keys(&:to_s))

      order.status = full_refund ? "refunded" : "partially_refunded"
      order.metadata = order.metadata.merge("refunds" => Array(order.metadata["refunds"]) + [ entry ])
      order.save!
    end

    def notify_buyer!(order, amount_cents:, reason:)
      refund_id = "ref_#{SecureRandom.alphanumeric(12)}"

      MatrixEventService.publish_refund_updated(
        refund_id: refund_id,
        order_id: order.order_id,
        buyer_user_id: order.buyer_user_id,
        amount: { amount: amount_cents, currency: order.currency },
        status: order.status,
        reason: reason
      )

      deliver_webhook(order, refund_id: refund_id)
    rescue StandardError => e
      # Notification is best-effort: the refund already happened.
      Rails.logger.error "[RefundService] refund notification failed for #{order.order_id}: #{e.message}"
    end

    def deliver_webhook(order, refund_id:)
      webhook_url = order.commerce_merchant.webhook_url
      return if webhook_url.blank?

      WebhookService.new.deliver(
        event_type: "commerce.refund.updated",
        payload: {
          refund_id: refund_id,
          order_id: order.order_id,
          checkout_id: order.metadata["checkout_id"],
          payment_id: order.payment_id,
          merchant_id: order.commerce_merchant.merchant_id,
          buyer_user_id: order.buyer_user_id,
          status: order.status
        },
        webhook_url: webhook_url
      )
    end
  end
end
