# frozen_string_literal: true

module Commerce
  # Walks a procurement down its pipeline and keeps the order's fulfilment
  # state in step, so the buyer sees progress without an operator having to
  # remember to update two records.
  #
  # The platform is the seller of record for the mirrored catalogue, so a
  # finished procurement is what "fulfilled" actually means for those orders.
  class ProcurementService
    class Error < StandardError; end

    def initialize(actor: nil, logger: Rails.logger)
      @actor = actor
      @logger = logger
    end

    def self.call(procurement, status:, attributes: {}, actor: nil)
      new(actor: actor).advance(procurement, status: status, attributes: attributes)
    end

    def advance(procurement, status:, attributes: {})
      status = status.to_s
      unless procurement.next_statuses.include?(status)
        raise Error, "a procurement that is #{procurement.status} cannot move to #{status}"
      end

      CommerceProcurement.transaction do
        procurement.assign_attributes(editable_attributes(attributes))
        procurement.status = status
        stamp = CommerceProcurement::STAMP_COLUMNS[status]
        procurement.public_send("#{stamp}=", Time.current) if stamp && procurement.public_send(stamp).nil?
        procurement.started_by_user_id ||= @actor&.matrix_user_id
        procurement.save!

        sync_order_fulfilment!(procurement.commerce_order)
      end

      procurement
    end

    private

    # Params arrive with string keys from the desk and symbol keys from jobs,
    # and `EDITABLE` is named for `permit`, so meet in the middle rather than
    # silently dropping half of what an operator typed.
    def editable_attributes(attributes)
      attributes.to_h.symbolize_keys.slice(*CommerceProcurement::EDITABLE.map(&:to_sym))
    end

    # An order is fulfilled exactly as far as its lines are. Only orders the
    # platform sells carry procurements; a merchant's order is left alone.
    def sync_order_fulfilment!(order)
      rows = order.commerce_procurements.reload
      return if rows.empty?

      deliverable = rows.reject { |row| row.status == "cancelled" }
      return if deliverable.empty?

      delivered = deliverable.count { |row| row.status == "delivered" }
      acted = deliverable.count { |row| CommerceProcurement::ACTED_STATUSES.include?(row.status) }

      order.fulfillment_status =
        if delivered == deliverable.size
          "fulfilled"
        elsif acted.positive?
          "partially_fulfilled"
        else
          "unfulfilled"
        end

      if order.fulfillment_status == "fulfilled" && order.status != "fulfilled"
        order.status = "fulfilled" if CommerceOrder::VALID_TRANSITIONS.fetch(order.status, []).include?("fulfilled")
      end

      order.save! if order.changed?
    end
  end
end
