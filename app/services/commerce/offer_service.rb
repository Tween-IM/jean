# frozen_string_literal: true

module Commerce
  # Structured offer lifecycle: proposing, counteroffering, accepting and
  # declining. Acceptance converts the immutable offer terms into a protected
  # CommerceOrder and asks Tween Pay to hold the funds.
  class OfferService
    class Error < StandardError; end
    class NotParticipantError < Error; end
    class NotRecipientError < Error; end
    class InvalidStateError < Error; end
    class ExpiredError < Error; end
    class PaymentError < Error; end

    # -------------------------------------------------------------------------
    # Proposing
    # -------------------------------------------------------------------------

    def create!(conversation, proposer_user_id, params)
      participant!(conversation, proposer_user_id)

      offer = build_offer(conversation, proposer_user_id, params)
      offer.status = "proposed"
      offer.expires_at = params[:expires_at].presence || 72.hours.from_now
      offer.save!

      offer
    end

    def counter!(offer, proposer_user_id, params)
      conversation = offer.commerce_conversation
      participant!(conversation, proposer_user_id)

      raise InvalidStateError, "only proposed offers can be countered" unless offer.status == "proposed"

      counter = build_offer(conversation, proposer_user_id, params,
                            parent_offer_id: (offer.parent_offer_id || offer.offer_id),
                            version: conversation.commerce_offers.maximum(:version).to_i + 1)
      counter.status = "proposed"
      counter.expires_at = params[:expires_at].presence || 72.hours.from_now
      counter.save!

      offer.update!(status: "superseded", superseded_by_offer_id: counter.offer_id,
                    responded_at: Time.current)
      counter
    end

    # -------------------------------------------------------------------------
    # Accepting
    # -------------------------------------------------------------------------

    # Optimistic-locking acceptance. The acceptor must be the recipient, the
    # offer must still be proposed and unexpired. On success a protected order
    # is created and a protected payment requested from Tween Pay.
    def accept!(offer, user_id)
      raise NotRecipientError, "only the offer recipient can accept" unless offer.recipient_user_id == user_id
      raise InvalidStateError, "offer is no longer open" unless offer.status == "proposed"
      raise ExpiredError, "offer has expired" if offer.expired?

      conversation = offer.commerce_conversation
      offer.status = "accepted"
      offer.accepted_by_user_id = user_id
      offer.accepted_at = Time.current
      offer.responded_at = Time.current

      order = nil
      ActiveRecord::Base.transaction do
        raise InvalidStateError, "offer was superseded" if offer.superseded?
        raise InvalidStateError, "offer has expired" if offer.expired?

        offer.save!
        order = create_protected_order!(offer, conversation)
        request_protected_payment!(order, offer)
      end

      order
    rescue ActiveRecord::StaleObjectError
      raise InvalidStateError, "offer changed while accepting; please retry"
    end

    def decline!(offer, user_id)
      raise NotRecipientError, "only the offer recipient can decline" unless offer.recipient_user_id == user_id
      raise InvalidStateError, "offer is no longer open" unless offer.status == "proposed"

      offer.update!(status: "declined", responded_at: Time.current)
      offer
    end

    private

    def build_offer(conversation, proposer_user_id, params, parent_offer_id: nil, version: 1)
      recipient = other_participant(conversation, proposer_user_id)
      offer_type = params[:offer_type].presence || "product"
      terms = params[:terms].is_a?(ActionController::Parameters) ? params[:terms].to_unsafe_h : (params[:terms] || {})
      terms = terms.deep_symbolize_keys

      totals = compute_totals(params, offer_type, terms)

      CommerceOffer.new(
        conversation_id: conversation.conversation_id,
        proposer_user_id: proposer_user_id,
        recipient_user_id: recipient,
        offer_type: offer_type,
        version: version,
        parent_offer_id: parent_offer_id,
        currency: params[:currency].presence || "NGN",
        subtotal_cents: params[:subtotal_cents].presence || totals[:subtotal_cents],
        delivery_fee_cents: params[:delivery_fee_cents].presence || totals[:delivery_fee_cents],
        buyer_fee_cents: params[:buyer_fee_cents].presence || totals[:buyer_fee_cents],
        discount_cents: params[:discount_cents].presence || totals[:discount_cents],
        total_cents: params[:total_cents].presence || totals[:total_cents],
        commission_cents: params[:commission_cents].presence || totals[:commission_cents],
        seller_proceeds_cents: params[:seller_proceeds_cents].presence || totals[:seller_proceeds_cents],
        terms_json: { terms_schema_version: 1 }.merge(terms)
      )
    end

    def compute_totals(params, _offer_type, _terms)
      subtotal = (params[:subtotal_cents].presence || 0).to_i
      delivery = (params[:delivery_fee_cents].presence || 0).to_i
      buyer_fee = (params[:buyer_fee_cents].presence || 0).to_i
      discount = (params[:discount_cents].presence || 0).to_i
      total = [ subtotal + delivery + buyer_fee - discount, 0 ].max

      commission_rate = params[:commission_rate].to_i
      commission = commission_rate.positive? ? (total * commission_rate / 100.0).round : 0
      {
        subtotal_cents: subtotal,
        delivery_fee_cents: delivery,
        buyer_fee_cents: buyer_fee,
        discount_cents: discount,
        total_cents: total,
        commission_cents: commission,
        seller_proceeds_cents: total - commission
      }
    end

    def create_protected_order!(offer, conversation)
      merchant = conversation.merchant
      terms = offer.terms_json.deep_symbolize_keys
      buyer_user_id = conversation.buyer_user_id
      order = CommerceOrder.create!(
        commerce_merchant: merchant,
        buyer_user_id: buyer_user_id,
        payment_id: "ppay_#{offer.offer_id}",
        status: "pending_payment",
        source: offer.offer_type == "service" ? "service_booking" : "conversation",
        protection_status: "eligible",
        fulfillment_type: offer.offer_type == "service" ? "service" : (terms[:delivery_method] == "pickup" ? "pickup" : "shipment"),
        terms_version: offer.version,
        accepted_offer_id: offer.offer_id,
        subtotal_cents: offer.subtotal_cents,
        tax_cents: 0,
        shipping_cents: offer.delivery_fee_cents,
        discount_cents: offer.discount_cents,
        total_cents: offer.total_cents,
        currency: offer.currency,
        metadata: { conversation_id: conversation.conversation_id }
      )

      add_order_items!(order, offer, terms)
      order
    end

    def add_order_items!(order, offer, terms)
      items = terms[:items]
      if items.present?
        Array(items).each do |item|
          order.commerce_order_items.create!(
            sku_id: item[:sku_id],
            product_id: item[:product_id],
            title: item[:title] || item[:product_name] || "Item",
            product_name: item[:product_name] || item[:title] || "Item",
            product_media_url: item[:product_media_url],
            variant_attributes: item[:variant_attributes] || {},
            quantity: item[:quantity] || 1,
            unit_price_cents: item[:unit_price_cents] || 0,
            line_total_cents: (item[:unit_price_cents] || 0) * (item[:quantity] || 1),
            currency: order.currency
          )
        end
      else
        product = order.commerce_merchant.commerce_products.find_by(product_id: terms[:product_id])
        if product
          sku = product.commerce_skus.order(created_at: :asc).first
          order.commerce_order_items.create!(
            sku_id: sku&.sku_id || "sku_#{product.product_id}",
            product_id: product.product_id,
            title: product.title,
            product_name: product.title,
            product_media_url: product.media_urls.first,
            quantity: terms[:quantity] || 1,
            unit_price_cents: offer.subtotal_cents,
            line_total_cents: offer.subtotal_cents,
            currency: order.currency
          )
        end
      end
    end

    def request_protected_payment!(order, offer)
      response = ProtectedCommerceService.create_payment(
        {
          order_id: order.order_id,
          buyer_user_id: order.buyer_user_id,
          seller_user_id: order.commerce_merchant.owner_user_id,
          merchant_id: order.commerce_merchant.merchant_id,
          currency: order.currency,
          gross_amount_cents: order.total_cents,
          seller_proceeds_cents: offer.seller_proceeds_cents,
          commission_cents: offer.commission_cents,
          provider_fee_cents: 0
        },
        idempotency_key: "offer_accept_#{offer.offer_id}"
      )

      protected_payment = response[:protected_payment] || response
      order.update!(
        protected_payment_id: protected_payment[:protected_payment_id],
        payment_id: protected_payment[:protected_payment_id],
        protection_status: "active"
      )
    rescue ProtectedCommerceService::Error => e
      raise PaymentError, "could not create protected payment: #{e.message}"
    end

    def participant!(conversation, user_id)
      return if conversation.buyer_user_id == user_id || conversation.seller_user_id == user_id

      raise NotParticipantError, "user is not a participant in this conversation"
    end

    def other_participant(conversation, user_id)
      conversation.buyer_user_id == user_id ? conversation.seller_user_id : conversation.buyer_user_id
    end
  end
end
