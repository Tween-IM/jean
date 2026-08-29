# frozen_string_literal: true

# Commerce deal notifications. Creates an in-app Notification row (read by the
# app's notifications list) and publishes a real push to the recipient's
# private Matrix notification room. Every notification carries order IDs only,
# never sensitive financial details.
class CommerceNotifier
  class << self
    def offer_received(offer)
      conversation = offer.commerce_conversation
      counterparty = offer.proposer_user_id == conversation.buyer_user_id ? conversation.seller_label : conversation.buyer_label
      notify(
        user_id: offer.recipient_user_id,
        title: "New protected deal",
        body: "#{counterparty} sent you a protected deal for #{format_money(offer.total_cents, offer.currency)}",
        order_id: nil,
        conversation_id: offer.conversation_id,
        deep_link: "tween://commerce/conversation/#{offer.conversation_id}"
      )
    end

    def offer_accepted(offer)
      conversation = offer.commerce_conversation
      counterparty = offer.recipient_user_id == conversation.buyer_user_id ? conversation.buyer_label : conversation.seller_label
      notify(
        user_id: offer.proposer_user_id,
        title: "Deal accepted",
        body: "#{counterparty} accepted your protected deal for #{format_money(offer.total_cents, offer.currency)}.",
        conversation_id: offer.conversation_id,
        deep_link: "tween://commerce/conversation/#{offer.conversation_id}"
      )
    end

    def offer_declined(offer)
      conversation = offer.commerce_conversation
      notify(
        user_id: offer.proposer_user_id,
        title: "Deal declined",
        body: "Your protected deal for #{format_money(offer.total_cents, offer.currency)} was declined.",
        conversation_id: offer.conversation_id,
        deep_link: "tween://commerce/conversation/#{offer.conversation_id}"
      )
    end

    def payment_funded(order)
      notify(
        user_id: order.commerce_merchant.owner_user_id,
        title: "Payment secured",
        body: "A buyer secured #{format_money(order.total_cents, order.currency)} on order #{order.order_id}. It will be released after delivery is confirmed.",
        order_id: order.order_id,
        deep_link: "tween://orders/#{order.order_id}"
      )
    end

    def payment_releasing(order)
      notify(
        user_id: order.commerce_merchant.owner_user_id,
        title: "Payment released",
        body: "#{format_money(order.total_cents, order.currency)} on order #{order.order_id} has been released to you.",
        order_id: order.order_id,
        deep_link: "tween://orders/#{order.order_id}"
      )
    end

    def payment_refunded(order)
      notify(
        user_id: order.buyer_user_id,
        title: "Payment refunded",
        body: "#{format_money(order.total_cents, order.currency)} on order #{order.order_id} was refunded to your wallet.",
        order_id: order.order_id,
        deep_link: "tween://orders/#{order.order_id}"
      )
    end

    def fulfilment_shipped(fulfillment)
      order = fulfillment.commerce_order
      notify(
        user_id: order.buyer_user_id,
        title: "Order shipped",
        body: "Your order #{order.order_id} has been shipped. Confirm delivery to start the inspection period.",
        order_id: order.order_id,
        deep_link: "tween://orders/#{order.order_id}"
      )
    end

    def inspection_started(order)
      notify(
        user_id: order.buyer_user_id,
        title: "Inspection period started",
        body: "Confirm delivery or report a problem within the inspection window on order #{order.order_id}.",
        order_id: order.order_id,
        deep_link: "tween://orders/#{order.order_id}"
      )
    end

    def delivery_declared(order)
      notify(
        user_id: order.buyer_user_id,
        title: "Item delivered",
        body: "The seller marked order #{order.order_id} as delivered. Confirm you received it to complete the purchase.",
        order_id: order.order_id,
        deep_link: "tween://orders/#{order.order_id}"
      )
    end

    def dispute_opened(order)
      notify(
        user_id: order.commerce_merchant.owner_user_id,
        title: "Dispute opened",
        body: "A dispute was opened on order #{order.order_id}. The payment is frozen while we review it.",
        order_id: order.order_id,
        deep_link: "tween://orders/#{order.order_id}"
      )
    end

    # Self-test: deliver a notification to the current viewer so the panel and
    # push path can be validated without going through a full order lifecycle.
    def test(user_id)
      notify(
        user_id: user_id,
        title: "Test notification",
        body: "This confirms notification delivery works.",
        deep_link: "tween://orders/test"
      )
    end

    private

    def notify(user_id:, title:, body:, order_id: nil, conversation_id: nil, deep_link: nil)
      return if user_id.blank?

      NotificationService.create_from_external(
        source: :commerce,
        user_id: user_id,
        notification_type: :system,
        title: title,
        body: body,
        target_type: order_id ? "commerce_order" : "commerce_offer",
        target_id: order_id,
        metadata: { conversation_id: conversation_id, deep_link: deep_link }.compact
      )
      MatrixEventService.publish_commerce_notification(
        user_id: user_id,
        event_type: "m.tween.commerce.notification",
        title: title,
        body: body,
        order_id: order_id,
        conversation_id: conversation_id,
        deep_link: deep_link
      )
    rescue StandardError => e
      Rails.logger.warn "[CommerceNotifier] failed to notify #{user_id}: #{e.message}"
    end

    def format_money(cents, currency)
      symbol = currency == "NGN" ? "₦" : "#{currency} "
      "#{symbol}#{cents.to_i / 100.0}"
    end
  end
end
