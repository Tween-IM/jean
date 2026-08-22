# frozen_string_literal: true

module Commerce
  # Fulfilment lifecycle for protected orders. Moves the first-class
  # CommerceFulfillment through its kind-specific state machine and drives the
  # protected-payment release schedule in Tween Pay.
  #
  # Release never depends exclusively on the buyer: delivery confirmation or
  # buyer acceptance starts the inspection window, and Jean schedules the
  # release at its deadline. Tween Pay's release worker performs the actual
  # money movement and rechecks dispute state.
  class FulfillmentService
    class Error < StandardError; end
    class NotAuthorizedError < Error; end
    class InvalidStateError < Error; end

    INSPECTION_HOURS = 24

    # -------------------------------------------------------------------------
    # Shipment / local delivery
    # -------------------------------------------------------------------------

    # Seller records a shipment with carrier/tracking details.
    def create_shipment!(order, actor, params = {})
      merchant_owner!(order, actor)

      fulfillment = order.commerce_fulfillments.create!(
        kind: params[:kind] || "shipment",
        provider: params[:carrier],
        tracking_number: params[:tracking_number],
        tracking_url: params[:tracking_url],
        status: "shipped",
        shipped_at: Time.current,
        updated_by_user_id: actor,
        metadata: params[:metadata] || {}
      )
      record_event!(fulfillment, "shipment.shipped", actor, params)
      order.update!(fulfillment_status: "partially_fulfilled")

      fulfillment
    end

    # Seller marks a pickup order ready for handover.
    def ready_for_pickup!(order, actor)
      merchant_owner!(order, actor)

      fulfillment = order.commerce_fulfillments.create!(
        kind: "pickup",
        status: "ready",
        updated_by_user_id: actor
      )
      record_event!(fulfillment, "pickup.ready", actor)
      order.update!(fulfillment_status: "partially_fulfilled")
      fulfillment
    end

    # Buyer generates a one-time handover code. Only shown once, stored hashed.
    def issue_pickup_code!(order, actor)
      buyer!(order, actor)

      fulfillment = order.commerce_fulfillments.active_or_latest
      raise InvalidStateError, "no pickup fulfilment" unless fulfillment&.kind == "pickup"
      unless fulfillment.status.in?(%w[ready handover_pending])
        raise InvalidStateError, "pickup is not ready for handover"
      end

      fulfillment.update!(status: "handover_pending", updated_by_user_id: actor)
      record_event!(fulfillment, "pickup.handover_pending", actor)
      ::CommercePickupCode.issue!(fulfillment, actor: actor)
    end

    # Seller confirms handover with the buyer's one-time code.
    def confirm_pickup!(order, actor, code)
      merchant_owner!(order, actor)

      fulfillment = order.commerce_fulfillments.active_or_latest
      raise InvalidStateError, "no pickup fulfilment" unless fulfillment&.kind == "pickup"
      unless fulfillment.status.in?(%w[handover_pending ready])
        raise InvalidStateError, "pickup is not awaiting handover"
      end

      ::CommercePickupCode.confirm!(fulfillment, code)
      fulfillment.update!(status: "handed_over", updated_by_user_id: actor)
      record_event!(fulfillment, "pickup.handed_over", actor)
      schedule_release!(order, Time.current + INSPECTION_HOURS.hours)
      fulfillment
    end

    # Buyer confirms they received the item. Starts the inspection window and
    # schedules automatic release at its deadline.
    def confirm_delivery!(order, actor, fulfillment = nil)
      buyer!(order, actor)

      fulfillment ||= order.commerce_fulfillments.active_or_latest
      raise InvalidStateError, "no shipment to confirm" unless fulfillment

      if fulfillment.kind == "service"
        return confirm_service!(order, actor, fulfillment)
      end

      unless fulfillment.status.in?(%w[delivered handed_over])
        raise InvalidStateError, "fulfilment cannot be confirmed from #{fulfillment.status}"
      end

      fulfillment.update!(status: "accepted", accepted_at: Time.current, updated_by_user_id: actor)
      record_event!(fulfillment, "fulfilment.accepted", actor)

      order.update!(fulfillment_status: "fulfilled", status: "processing",
                    metadata: order.metadata.merge("inspection_started_at" => Time.current.iso8601))
      schedule_release!(order, Time.current + INSPECTION_HOURS.hours)

      { fulfillment: fulfillment, inspection_deadline: Time.current + INSPECTION_HOURS.hours }
    end

    # Buyer explicitly accepts the delivery (skips the rest of the inspection
    # window) and release is scheduled immediately.
    def accept_delivery!(order, actor)
      buyer!(order, actor)

      fulfillment = order.commerce_fulfillments.active_or_latest
      raise InvalidStateError, "no fulfilment to accept" unless fulfillment

      unless fulfillment.status.in?(%w[delivered handed_over accepted])
        raise InvalidStateError, "fulfilment cannot be accepted from #{fulfillment.status}"
      end

      fulfillment.update!(status: "accepted", accepted_at: Time.current, updated_by_user_id: actor) unless fulfillment.status == "accepted"
      order.update!(fulfillment_status: "fulfilled", status: "fulfilled")
      schedule_release!(order, Time.current)

      fulfillment
    end

    # -------------------------------------------------------------------------
    # Service fulfilment
    # -------------------------------------------------------------------------

    def begin_service!(order, actor)
      merchant_owner!(order, actor)
      fulfillment = order.commerce_fulfillments.create!(
        kind: "service",
        status: "scheduled",
        updated_by_user_id: actor
      )
      record_event!(fulfillment, "service.scheduled", actor)
      fulfillment
    end

    # Seller submits completion evidence; evidence is append-only after this.
    def submit_service!(order, actor, evidence: [])
      merchant_owner!(order, actor)

      fulfillment = order.commerce_fulfillments.active_or_latest
      fulfillment ||= begin_service!(order, actor)

      unless fulfillment.status.in?(%w[in_progress scheduled submitted revision_requested])
        raise InvalidStateError, "cannot submit from #{fulfillment.status}"
      end

      fulfillment.update!(status: "submitted", updated_by_user_id: actor)
      record_event!(fulfillment, "service.submitted", actor, { evidence: Array(evidence) })

      order.update!(fulfillment_status: "partially_fulfilled", status: "processing")
      fulfillment
    end

    def confirm_service!(order, actor, fulfillment)
      buyer!(order, actor)
      unless fulfillment.status.in?(%w[inspection submitted accepted])
        raise InvalidStateError, "cannot confirm service from #{fulfillment.status}"
      end

      fulfillment.update!(status: "accepted", accepted_at: Time.current, updated_by_user_id: actor)
      order.update!(fulfillment_status: "fulfilled", status: "fulfilled")
      schedule_release!(order, Time.current)
      fulfillment
    end

    def request_revision!(order, actor)
      buyer!(order, actor)

      fulfillment = order.commerce_fulfillments.active_or_latest
      raise InvalidStateError, "no fulfilment to revise" unless fulfillment

      unless fulfillment.status.in?(%w[submitted inspection])
        raise InvalidStateError, "cannot request revision from #{fulfillment.status}"
      end

      fulfillment.update!(status: "revision_requested", updated_by_user_id: actor)
      record_event!(fulfillment, "service.revision_requested", actor)
      fulfillment
    end

    # -------------------------------------------------------------------------
    # Milestones (service orders)
    # -------------------------------------------------------------------------

    # A participant proposes a new milestone on a service order.
    def add_milestone!(order, actor, params = {})
      participant!(order, actor)
      raise InvalidStateError, "milestones apply to service orders only" unless order.is_service_order?

      order.commerce_service_milestones.create!(
        title: params[:title].presence || "Milestone",
        description: params[:description],
        amount_cents: params[:amount_cents].to_i,
        currency: order.currency,
        scheduled_at: params[:scheduled_at],
        status: "pending"
      )
    end

    # Seller submits completion evidence for a milestone.
    def submit_milestone!(order, actor, milestone, evidence: [])
      merchant_owner!(order, actor)

      unless milestone.status.in?(%w[pending in_progress])
        raise InvalidStateError, "milestone cannot be submitted from #{milestone.status}"
      end

      milestone.update!(status: "submitted", evidence: Array(evidence))
      milestone
    end

    # Buyer accepts a completed milestone; the milestone amount is released.
    def accept_milestone!(order, actor, milestone)
      buyer!(order, actor)

      unless milestone.status == "submitted"
        raise InvalidStateError, "milestone is not awaiting acceptance"
      end

      milestone.update!(status: "accepted", completed_at: Time.current)
      release_milestone!(order, milestone)
      milestone
    end

    # Release a single milestone amount via Tween Pay partial release.
    def release_milestone!(order, milestone)
      return milestone if milestone.released?

      raise Error, "milestone amount must be positive" unless milestone.amount_cents.positive?

      ProtectedCommerceService.release(
        order.protected_payment_id,
        actor: "milestone_worker",
        trigger: "milestone",
        amount_cents: milestone.amount_cents
      )
      milestone.update!(status: "released", released_at: Time.current)
      fulfillment = order.commerce_fulfillments.active_or_latest
      record_event!(fulfillment, "milestone.released", "system",
                    { milestone_id: milestone.milestone_id, amount_cents: milestone.amount_cents }) if fulfillment
      milestone
    rescue ProtectedCommerceService::Error => e
      raise Error, "could not release milestone: #{e.message}"
    end

    private

    def schedule_release!(order, release_at)
      return unless order.protected_payment_id.present?

      ProtectedCommerceService.schedule_release(order.protected_payment_id, release_at: release_at.iso8601)
    rescue ProtectedCommerceService::Error => e
      raise Error, "could not schedule release: #{e.message}"
    end

    def record_event!(fulfillment, event_type, actor, data = {})
      fulfillment.events.create!(event_type: event_type, actor_user_id: actor, data: data)
    end

    def buyer!(order, actor)
      return if order.buyer_user_id == actor

      raise NotAuthorizedError, "only the buyer can do this"
    end

    def merchant_owner!(order, actor)
      return if order.commerce_merchant.owner_user_id == actor

      raise NotAuthorizedError, "only the seller can do this"
    end

    def participant!(order, actor)
      return if order.buyer_user_id == actor || order.commerce_merchant.owner_user_id == actor

      raise NotAuthorizedError, "only order participants can do this"
    end
  end
end
