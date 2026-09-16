# frozen_string_literal: true

module Admin
  # Order operations for the platform's own merchant.
  #
  # Imported catalogues hang off the system merchant, which has no human
  # owner, so nobody could move those orders forward in the apps. This surface
  # is that missing operator seat: it does the same state machine the merchant
  # app drives (`Commerce::FulfillmentService`, `CommerceOrder::VALID_TRANSITIONS`)
  # with a platform-admin actor, and refuses anything the model would refuse.
  class OrdersController < BaseController
    OPEN_STATUSES = %w[pending_payment paid processing partially_fulfilled].freeze
    ATTENTION_STATUSES = %w[pending_payment paid processing].freeze
    PERIODS = { "24h" => 1.day, "7d" => 7.days, "30d" => 30.days, "90d" => 90.days }.freeze
    SORTS = { "newest" => :newest, "oldest" => :oldest, "value" => :value }.freeze
    FULFILLMENT_ACTIONS = %w[ship deliver confirm ready_for_pickup confirm_pickup accept].freeze

    before_action :require_view_orders!
    before_action :require_manage_orders!, only: [ :transition, :fulfillment, :payment ]
    before_action :require_manage_refunds!, only: [ :refund ]
    before_action :set_order, only: [ :show, :transition, :refund, :fulfillment, :payment ]

    def index
      @stats = stats
      @orders = paginate(order_scope.includes(:commerce_merchant, :commerce_order_items))
      @merchants = CommerceMerchant.order(:display_name).limit(200)
      @statuses = %w[pending_payment paid processing fulfilled partially_fulfilled cancelled refunded partially_refunded]
      @fulfillment_statuses = %w[not_required unfulfilled partially_fulfilled fulfilled failed]
      @sources = CommerceOrder::SOURCES
      @periods = PERIODS.keys
    end

    def show
      @items = @order.commerce_order_items.order(:id)
      @fulfillments = @order.commerce_fulfillments.order(created_at: :desc)
      @events = CommerceFulfillmentEvent
        .where(commerce_fulfillment_id: @fulfillments.map(&:id))
        .order(created_at: :desc)
        .limit(50)
      @buyer = User.find_by(matrix_user_id: @order.buyer_user_id)
      @merchant = @order.commerce_merchant
      @products_by_id = products_by_id_for(@items)
      @storefronts = storefronts_for(@items)
      @next_statuses = CommerceOrder::VALID_TRANSITIONS.fetch(@order.status, [])
      @refunds = Array(@order.metadata["refunds"])
      @timeline = Array(@order.metadata["timeline"]).reverse
      @protected_payment = @order.metadata["protected_payment"].is_a?(Hash) ? @order.metadata["protected_payment"] : nil
      @disputes = @order.commerce_disputes.order(created_at: :desc).limit(10)
    end

    # Legal status moves only; the model's transition table is the source of
    # truth, and moving to a fulfilled state also settles fulfillment_status.
    def transition
      target = params[:status].to_s
      allowed = CommerceOrder::VALID_TRANSITIONS.fetch(@order.status, [])

      unless allowed.include?(target)
        return redirect_to admin_order_path(@order),
          alert: "#{@order.status.humanize} → #{target.humanize} is not a legal order transition."
      end

      attributes = { status: target }
      case target
      when "fulfilled" then attributes[:fulfillment_status] = "fulfilled"
      when "partially_fulfilled" then attributes[:fulfillment_status] = "partially_fulfilled"
      end

      cancel_protected_release(target)

      if @order.update(attributes.merge(metadata: stamped_metadata("transition", target)))
        log_admin_action("transition_order", @order.order_id, from: @order.status_previously_was, to: target)
        redirect_to admin_order_path(@order), notice: "Order is now #{target.humanize.downcase}."
      else
        message = @order.errors.full_messages.to_sentence.presence ||
          "#{@order.status} cannot move to #{target} right now."
        redirect_to admin_order_path(@order), alert: "Could not change the order: #{message}"
      end
    end

    # Logistics: the same calls the seller app makes, as the platform actor.
    def fulfillment
      action = params[:fulfillment_action].to_s
      unless FULFILLMENT_ACTIONS.include?(action)
        return redirect_to admin_order_path(@order), alert: "Unknown fulfilment action."
      end

      actor = current_admin_user.matrix_user_id
      result = run_fulfillment(action, actor)

      log_admin_action("fulfil_order", @order.order_id, action: action, fulfillment_id: result.is_a?(Hash) ? result[:fulfillment]&.fulfillment_id : result&.fulfillment_id)
      redirect_to admin_order_path(@order), notice: fulfillment_notice(action, result)
    rescue ::Commerce::FulfillmentService::InvalidStateError => e
      redirect_to admin_order_path(@order), alert: e.message
    rescue ::Commerce::FulfillmentService::NotAuthorizedError => e
      redirect_to admin_order_path(@order), alert: e.message
    rescue ::Commerce::FulfillmentService::Error => e
      redirect_to admin_order_path(@order), alert: "Could not update the fulfilment: #{e.message}"
    end

    def refund
      result = ::Commerce::RefundService.new.call(
        order: @order,
        amount_cents: params[:amount_cents],
        reason: params[:reason].presence || "platform_refund",
        actor: current_admin_user.matrix_user_id,
        metadata: { "channel" => "admin", "admin_user_id" => current_admin_user.id }
      )

      log_admin_action("refund_order", @order.order_id,
        amount_cents: result.amount_cents, full_refund: result.full_refund, channel: result.channel)

      redirect_to admin_order_path(@order),
        notice: "#{result.full_refund ? 'Full' : 'Partial'} refund of #{helpers.number_to_currency(result.amount_cents / 100.0, unit: @order.currency + ' ')} recorded."
    rescue ::Commerce::RefundService::Error => e
      redirect_to admin_order_path(@order), alert: e.message
    end

    # Pull the authoritative state of the protected payment out of Tween Pay
    # and keep a snapshot on the order, so operators can see the ledger without
    # a database session.
    def payment
      if @order.protected_payment_id.blank?
        return redirect_to admin_order_path(@order), alert: "This order is not a protected payment."
      end

      snapshot = ProtectedCommerceService.get_payment(@order.protected_payment_id)
      @order.update!(metadata: @order.metadata.merge(
        "protected_payment" => { "synced_at" => Time.current.iso8601, "payload" => snapshot }
      ))
      log_admin_action("sync_protected_payment", @order.order_id, protected_payment_id: @order.protected_payment_id)
      redirect_to admin_order_path(@order), notice: "Protected payment refreshed from Tween Pay."
    rescue ProtectedCommerceService::Error => e
      redirect_to admin_order_path(@order), alert: "Tween Pay refused the lookup: #{e.message}"
    end

    private

    def set_order
      @order = CommerceOrder.includes(:commerce_merchant).find(params[:id])
    end

    def run_fulfillment(action, actor)
      service = ::Commerce::FulfillmentService.new(platform_admin: true)

      case action
      when "ship"
        service.create_shipment!(@order, actor,
          kind: params[:kind].presence || "shipment",
          carrier: params[:carrier],
          tracking_number: params[:tracking_number],
          tracking_url: params[:tracking_url],
          metadata: { "recorded_by_admin" => current_admin_user.id })
      when "deliver"
        service.mark_delivered!(@order, actor, note: params[:note])
      when "confirm"
        service.confirm_delivery!(@order, actor)
      when "ready_for_pickup"
        service.ready_for_pickup!(@order, actor)
      when "confirm_pickup"
        service.confirm_pickup!(@order, actor, params[:pickup_code].to_s)
      when "accept"
        service.accept_delivery!(@order, actor)
      end
    end

    def fulfillment_notice(action, result)
      fulfillment = result.is_a?(Hash) ? result[:fulfillment] : result
      case action
      when "ship" then "Shipment recorded (#{fulfillment.fulfillment_id})."
      when "deliver" then "Marked as delivered — the buyer (or the inspection window) releases the funds."
      when "confirm" then "Delivery confirmed on the buyer's behalf; release scheduled."
      when "ready_for_pickup" then "Order is ready for pickup."
      when "confirm_pickup" then "Pickup confirmed and release scheduled."
      when "accept" then "Delivery accepted; release scheduled."
      else "Fulfilment updated."
      end
    end

    # Cancelling a protected order must also drop the scheduled release, or
    # Tween Pay would pay out a cancelled order.
    def cancel_protected_release(target)
      return unless target == "cancelled"
      return if @order.protected_payment_id.blank?

      ProtectedCommerceService.cancel_release(@order.protected_payment_id, actor: current_admin_user.matrix_user_id)
    rescue ProtectedCommerceService::Error => e
      Rails.logger.warn "[Admin::OrdersController] cancel_release failed for #{@order.order_id}: #{e.message}"
    end

    def stamped_metadata(action, value)
      @order.metadata.merge(
        "timeline" => Array(@order.metadata["timeline"]) + [ {
          "action" => action,
          "value" => value,
          "by" => current_admin_user.matrix_user_id,
          "at" => Time.current.iso8601
        } ]
      )
    end

    # Line items carry the name and image the buyer saw at checkout; the live
    # listing fills in when an older item recorded neither.
    def products_by_id_for(items)
      product_ids = items.map(&:product_id).compact.uniq
      return {} if product_ids.empty?

      CommerceProduct.where(product_id: product_ids).index_by(&:product_id)
    end

    def storefronts_for(items)
      products = products_by_id_for(items).values
      return [] if products.empty?

      CommerceStorefront.where(id: products.map(&:commerce_storefront_id).compact.uniq).order(:display_name)
    end

    def order_scope
      scope = CommerceOrder.all
      scope = scope.where(status: params[:status]) if params[:status].present?
      scope = scope.where(fulfillment_status: params[:fulfillment_status]) if params[:fulfillment_status].present?
      scope = scope.where(source: params[:source]) if params[:source].present?
      scope = scope.where(commerce_merchant_id: merchant_scope_ids) if params[:merchant].present?
      scope = scope.where(id: attention_orders.select(:id)) if params[:attention] == "1"
      scope = scope.where("created_at >= ?", PERIODS[params[:period]].ago) if PERIODS.key?(params[:period])
      scope = search(scope)

      case params[:sort]
      when "oldest" then scope.order(created_at: :asc)
      when "value" then scope.order(total_cents: :desc, created_at: :desc)
      else scope.order(created_at: :desc)
      end
    end

    def merchant_scope_ids
      if params[:merchant] == "system"
        CommerceMerchant.system_owned.select(:id)
      else
        CommerceMerchant.where(merchant_id: params[:merchant]).select(:id)
      end
    end

    # Orders that need a human: money is in but nothing has shipped, or the
    # buyer has not paid yet.
    def attention_orders
      CommerceOrder
        .where(status: ATTENTION_STATUSES, fulfillment_status: %w[unfulfilled partially_fulfilled])
        .or(CommerceOrder.where(status: "pending_payment"))
    end

    def search(scope)
      term = params[:query].to_s.strip
      return scope if term.blank?

      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term.downcase)}%"
      scope.where(
        "LOWER(order_id) LIKE :pattern OR LOWER(payment_id) LIKE :pattern " \
        "OR LOWER(buyer_user_id) LIKE :pattern OR LOWER(COALESCE(protected_payment_id, '')) LIKE :pattern",
        pattern: pattern
      )
    end

    def stats
      base = CommerceOrder.all
      {
        total: base.count,
        open: base.where(status: OPEN_STATUSES).count,
        unpaid: base.where(status: "pending_payment").count,
        needs_fulfillment: base.where(status: %w[paid processing], fulfillment_status: %w[unfulfilled partially_fulfilled]).count,
        system_open: base.where(commerce_merchant_id: CommerceMerchant.system_owned.select(:id), status: OPEN_STATUSES).count,
        gmv_30d_cents: base.where(status: %w[paid processing fulfilled partially_fulfilled])
          .where("created_at >= ?", 30.days.ago).sum(:total_cents),
        refunded_30d_cents: base.where(status: %w[refunded partially_refunded])
          .where("updated_at >= ?", 30.days.ago).sum(:total_cents)
      }
    end

    def require_view_orders!
      require_admin_permission!(:view_orders)
    end

    def require_manage_orders!
      require_admin_permission!(:manage_orders)
    end

    def require_manage_refunds!
      require_admin_permission!(:manage_refunds)
    end
  end
end
