# frozen_string_literal: true

# Commerce deal notifications. Every notification routes through
# NotificationDispatcher, which handles in-app records, FCM push,
# and email (for money-moving events) based on user preferences.
#
# Push carries order IDs only — never sensitive financial details.
class CommerceNotifier
  class << self
    def offer_received(offer)
      conversation = offer.commerce_conversation
      counterparty = offer.proposer_user_id == conversation.buyer_user_id ? conversation.seller_label : conversation.buyer_label
      dispatch(
        user_id: offer.recipient_user_id,
        notification_type: :system,
        title: "New protected deal",
        body: "#{counterparty} sent you a protected deal for #{format_money(offer.total_cents, offer.currency)}",
        deep_link: "tween://commerce/conversation/#{offer.conversation_id}",
        metadata: { conversation_id: offer.conversation_id }
      )
    end

    def offer_accepted(offer)
      conversation = offer.commerce_conversation
      counterparty = offer.recipient_user_id == conversation.buyer_user_id ? conversation.seller_label : conversation.buyer_label
      dispatch(
        user_id: offer.proposer_user_id,
        notification_type: :system,
        title: "Deal accepted",
        body: "#{counterparty} accepted your protected deal for #{format_money(offer.total_cents, offer.currency)}.",
        deep_link: "tween://commerce/conversation/#{offer.conversation_id}",
        metadata: { conversation_id: offer.conversation_id }
      )
    end

    def offer_declined(offer)
      conversation = offer.commerce_conversation
      dispatch(
        user_id: offer.proposer_user_id,
        notification_type: :system,
        title: "Deal declined",
        body: "Your protected deal for #{format_money(offer.total_cents, offer.currency)} was declined.",
        deep_link: "tween://commerce/conversation/#{offer.conversation_id}",
        metadata: { conversation_id: offer.conversation_id }
      )
    end

    def payment_funded(order)
      dispatch(
        user_id: order.commerce_merchant.owner_user_id,
        notification_type: :payment,
        title: "Payment secured",
        body: "A buyer secured #{format_money(order.total_cents, order.currency)} on order #{order.order_id}. It will be released after delivery is confirmed.",
        deep_link: "tween://orders/#{order.order_id}",
        metadata: { order_id: order.order_id }
      )
    end

    def payment_releasing(order)
      dispatch(
        user_id: order.commerce_merchant.owner_user_id,
        notification_type: :payment,
        title: "Payment released",
        body: "#{format_money(order.total_cents, order.currency)} on order #{order.order_id} has been released to you.",
        deep_link: "tween://orders/#{order.order_id}",
        metadata: { order_id: order.order_id }
      )
    end

    def payment_refunded(order)
      dispatch(
        user_id: order.buyer_user_id,
        notification_type: :payment,
        title: "Payment refunded",
        body: "#{format_money(order.total_cents, order.currency)} on order #{order.order_id} was refunded to your wallet.",
        deep_link: "tween://orders/#{order.order_id}",
        metadata: { order_id: order.order_id }
      )
    end

    def fulfilment_shipped(fulfillment)
      order = fulfillment.commerce_order
      dispatch(
        user_id: order.buyer_user_id,
        notification_type: :system,
        title: "Order shipped",
        body: "Your order #{order.order_id} has been shipped. Confirm delivery to start the inspection period.",
        deep_link: "tween://orders/#{order.order_id}",
        metadata: { order_id: order.order_id }
      )
    end

    def inspection_started(order)
      dispatch(
        user_id: order.buyer_user_id,
        notification_type: :system,
        title: "Inspection period started",
        body: "Confirm delivery or report a problem within the inspection window on order #{order.order_id}.",
        deep_link: "tween://orders/#{order.order_id}",
        metadata: { order_id: order.order_id }
      )
    end

    def delivery_declared(order)
      dispatch(
        user_id: order.buyer_user_id,
        notification_type: :system,
        title: "Item delivered",
        body: "The seller marked order #{order.order_id} as delivered. Confirm you received it to complete the purchase.",
        deep_link: "tween://orders/#{order.order_id}",
        metadata: { order_id: order.order_id }
      )
    end

    def confirmed(order)
      dispatch(
        user_id: order.commerce_merchant.owner_user_id,
        notification_type: :payment,
        title: "Order confirmed",
        body: "The buyer confirmed delivery on order #{order.order_id}. Your payment is being released.",
        deep_link: "tween://orders/#{order.order_id}",
        metadata: { order_id: order.order_id }
      )
    end

    def dispute_opened(order)
      dispatch(
        user_id: order.commerce_merchant.owner_user_id,
        notification_type: :payment,
        title: "Dispute opened",
        body: "A dispute was opened on order #{order.order_id}. The payment is frozen while we review it.",
        deep_link: "tween://orders/#{order.order_id}",
        metadata: { order_id: order.order_id }
      )
    end

    def test(user_id)
      dispatch(
        user_id: user_id,
        notification_type: :system,
        title: "Test notification",
        body: "This confirms notification delivery works.",
        deep_link: "tween://orders/test"
      )
    end

    private

    def dispatch(user_id:, notification_type: :system, title:, body:, deep_link: nil, metadata: {})
      return if user_id.blank?

      NotificationDispatcher.notify(
        user_id: user_id,
        source: :commerce,
        notification_type: notification_type,
        title: title,
        body: body,
        target_type: metadata[:order_id] ? "commerce_order" : "commerce_offer",
        target_id: metadata[:order_id],
        deep_link: deep_link,
        metadata: metadata
      )
    end

    def format_money(cents, currency)
      symbol = currency == "NGN" ? "₦" : "#{currency} "
      "#{symbol}#{cents.to_i / 100.0}"
    end
  end
end
