# frozen_string_literal: true

module Admin
  # The sourcing desk.
  #
  # The platform sells the mirrored catalogue itself and holds none of it, so
  # every paid order for an imported listing is a purchase somebody has to go
  # and make. This is the queue: what to buy, from whom, where, for how much,
  # and where it has to end up.
  class ProcurementsController < BaseController
    DONE_STATUSES = %w[delivered cancelled].freeze
    SORTS = %w[oldest newest cost].freeze

    before_action :require_view_fulfillment!
    before_action :require_manage_fulfillment!, only: [ :advance ]
    before_action :set_procurement, only: [ :show, :advance ]

    def index
      @stats = stats
      @procurements = paginate(scope.includes(:commerce_order, commerce_order_item: :product))
      @statuses = CommerceProcurement::STATUSES
      @platforms = CommerceProcurement.where.not(supplier_platform: [ nil, "" ]).distinct.pluck(:supplier_platform).sort
    end

    def show
      @order = @procurement.commerce_order
      @item = @procurement.commerce_order_item
      @product = @item.product
    end

    # One action for the whole pipeline: the operator says where it has got to
    # and hands over whatever that step needed (what it cost, the source order
    # number, the courier and tracking).
    def advance
      status = params[:status].to_s
      Commerce::ProcurementService.call(
        @procurement,
        status: status,
        attributes: procurement_params,
        actor: current_admin_user
      )
      log_admin_action("advance_procurement", @procurement.id, status: status, cost_cents: procurement_params[:cost_cents])

      redirect_to admin_procurement_path(@procurement),
        notice: "Sourcing moved to #{status}. The order follows it."
    rescue Commerce::ProcurementService::Error => e
      redirect_to admin_procurement_path(@procurement), alert: e.message
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_procurement_path(@procurement),
        alert: "Could not save: #{e.record.errors.full_messages.to_sentence}"
    end

    private

    def set_procurement
      @procurement = CommerceProcurement.find(params[:id])
    end

    def procurement_params
      params.fetch(:commerce_procurement, {}).permit(*CommerceProcurement::EDITABLE).to_h.symbolize_keys
    end

    def scope
      relation = case params[:status].presence
      when "open" then CommerceProcurement.open
      when nil, "" then CommerceProcurement.open
      else CommerceProcurement.where(status: params[:status])
      end

      relation = relation.where(supplier_platform: params[:platform]) if params[:platform].present?
      if params[:query].present?
        like = "%#{params[:query].strip}%"
        relation = relation.joins(:commerce_order_item).where(
          "commerce_procurements.supplier_name ILIKE :q OR commerce_procurements.external_order_ref ILIKE :q " \
          "OR commerce_order_items.title ILIKE :q", q: like
        )
      end
      relation = relation.where("commerce_procurements.created_at < ?", 2.days.ago) if params[:aged] == "1"

      case params[:sort]
      when "newest" then relation.order(created_at: :desc)
      when "cost" then relation.order(Arel.sql("cost_cents DESC NULLS LAST"))
      else relation.order(created_at: :asc)
      end
    end

    def stats
      base = CommerceProcurement.all
      {
        total: base.count,
        awaiting_purchase: base.awaiting_purchase.count,
        in_flight: base.where(status: %w[ordered received]).count,
        dispatched: base.where(status: "dispatched").count,
        delivered: base.delivered.count,
        #: Nobody has touched it and the buyer has been waiting.
        stale: base.awaiting_purchase.where("created_at < ?", 1.day.ago).count,
        committed_cents: base.where.not(cost_cents: nil).sum(:cost_cents)
      }
    end

    def require_view_fulfillment!
      require_admin_permission!(:view_fulfillment)
    end

    def require_manage_fulfillment!
      require_admin_permission!(:manage_fulfillment)
    end
  end
end
