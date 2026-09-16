# frozen_string_literal: true

module Admin
  # Merchant accounts: who sells on Tween, whether they are verified, what the
  # platform takes, and — for the system merchant — where the mirrored
  # catalogues live.
  class MerchantsController < BaseController
    STATUSES = %w[pending_review active suspended closed].freeze

    before_action :require_view_merchants!
    before_action :require_manage_merchants!, only: [ :update, :verify, :suspend, :reactivate ]
    before_action :set_merchant, only: [ :show, :update, :verify, :suspend, :reactivate ]

    def index
      @stats = stats
      @merchants = paginate(merchant_scope)
      @statuses = STATUSES

      # One grouped query each, rather than counting per row.
      merchant_ids = @merchants.records.map(&:id)
      @store_counts = CommerceStorefront.where(commerce_merchant_id: merchant_ids).group(:commerce_merchant_id).count
      @product_counts = CommerceProduct.where(commerce_merchant_id: merchant_ids).group(:commerce_merchant_id).count
    end

    def show
      @owner = User.find_by(matrix_user_id: @merchant.owner_user_id)
      @storefronts = @merchant.commerce_storefronts.order(:display_name)
      @orders = @merchant.commerce_orders.order(created_at: :desc).limit(10)
      @order_count = @merchant.commerce_orders.count
      @gmv_cents = @merchant.commerce_orders.where(status: %w[paid processing fulfilled partially_fulfilled]).sum(:total_cents)
      @payouts = CommercePayout.where(commerce_merchant_id: @merchant.id).order(created_at: :desc).limit(10)
      @products_count = @merchant.commerce_products.count
      @open_orders = @merchant.commerce_orders.where(status: OrdersController::OPEN_STATUSES).count
    end

    def update
      if @merchant.update(merchant_params)
        log_admin_action("update_merchant", @merchant.merchant_id, merchant_params.to_h)
        redirect_to admin_merchant_path(@merchant), notice: "Merchant updated."
      else
        flash.now[:alert] = "Could not save: #{@merchant.errors.full_messages.to_sentence}"
        show
        render :show, status: :unprocessable_entity
      end
    end

    def verify
      @merchant.update!(verified_at: Time.current, status: "active")
      log_admin_action("verify_merchant", @merchant.merchant_id)
      redirect_to admin_merchant_path(@merchant), notice: "Merchant verified."
    end

    def suspend
      @merchant.update!(status: "suspended")
      log_admin_action("suspend_merchant", @merchant.merchant_id)
      redirect_to admin_merchant_path(@merchant),
        notice: "Merchant suspended. Live listings stay published until you archive them."
    end

    def reactivate
      @merchant.update!(status: "active")
      log_admin_action("reactivate_merchant", @merchant.merchant_id)
      redirect_to admin_merchant_path(@merchant), notice: "Merchant reactivated."
    end

    private

    def set_merchant
      @merchant = CommerceMerchant.find(params[:id])
    end

    def merchant_scope
      scope = CommerceMerchant.all
      if params[:query].present?
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(params[:query].to_s.strip.downcase)}%"
        scope = scope.where(
          "LOWER(display_name) LIKE :pattern OR LOWER(merchant_id) LIKE :pattern OR LOWER(COALESCE(owner_user_id, '')) LIKE :pattern",
          pattern: pattern
        )
      end
      scope = scope.where(status: params[:status]) if params[:status].present?
      scope = scope.where(business_type: params[:business_type]) if params[:business_type].present?
      scope = scope.system_owned if params[:ownership] == "system"
      scope = scope.where(system_owned: false) if params[:ownership] == "merchant"
      scope = scope.where.not(verified_at: nil) if params[:verified] == "1"

      case params[:sort]
      when "orders"
        scope.order(Arel.sql(
          "(SELECT COUNT(*) FROM commerce_orders WHERE commerce_orders.commerce_merchant_id = commerce_merchants.id) DESC"
        ))
      when "gmv"
        scope.order(Arel.sql(
          "(SELECT COALESCE(SUM(total_cents), 0) FROM commerce_orders WHERE commerce_orders.commerce_merchant_id = commerce_merchants.id " \
          "AND commerce_orders.status IN ('paid', 'processing', 'fulfilled', 'partially_fulfilled')) DESC"
        ))
      else scope.order(system_owned: :desc, display_name: :asc)
      end
    end

    def stats
      {
        total: CommerceMerchant.count,
        active: CommerceMerchant.where(status: "active").count,
        pending: CommerceMerchant.where(status: "pending_review").count,
        suspended: CommerceMerchant.where(status: "suspended").count,
        verified: CommerceMerchant.where.not(verified_at: nil).count,
        system: CommerceMerchant.system_owned.count
      }
    end

    def merchant_params
      params.require(:commerce_merchant).permit(
        :display_name, :about, :email, :phone, :website, :business_type,
        :registration_number, :address_line1, :address_line2, :city, :state,
        :country, :commission_rate, :webhook_url, :status
      )
    end

    def require_view_merchants!
      require_admin_permission!(:view_merchants)
    end

    def require_manage_merchants!
      require_admin_permission!(:manage_merchants)
    end
  end
end
