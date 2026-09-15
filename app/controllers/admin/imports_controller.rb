# frozen_string_literal: true

module Admin
  # Monitor and curate catalogs imported from external marketplaces
  # (Jumia, Konga, ...) by the tween-scraper service.
  #
  # Imports land through the commerce import API (see
  # `docs/commerce_catalog_import.md`); this is the operator view of what
  # arrived: which source stores exist, what they brought in, whether we have
  # a way to reach the seller, and how fresh the data is.
  #
  # "Setting things" here means correcting what the scraper cannot know:
  # branding, the contact details the platform team collects out of band, and
  # whether a store, listing or imported review is live.
  class ImportsController < BaseController
    # Imported rows older than this are surfaced as needing a re-sync.
    STALE_AFTER = 7.days

    # Product states an operator may set from here.
    PRODUCT_STATUSES = %w[active draft archived].freeze
    # Review states an operator may set from here.
    REVIEW_STATUSES = %w[approved pending rejected].freeze

    before_action :require_view_imports!
    before_action :require_manage_imports!,
      only: [ :update_storefront, :update_product, :update_review, :create_system_merchant ]
    before_action :set_storefront, only: [ :show_storefront, :update_storefront ]
    before_action :set_product, only: [ :show_product, :update_product ]
    before_action :set_review, only: [ :update_review ]

    # ── Monitoring overview ──────────────────────────────────────────────

    def index
      imported_products = CommerceProduct.imported
      imported_storefronts = CommerceStorefront.imported
      imported_reviews = CommerceReview.imported

      # Everything an import creates hangs off the platform-owned merchant.
      @system_merchant = CommerceMerchant.system_owned.order(:id).first
      @stats = {
        storefronts: imported_storefronts.count,
        products: imported_products.count,
        reviews: imported_reviews.count,
        anonymous_reviews: imported_reviews.where(is_anonymous: true).count,
        stores_without_contact: imported_storefronts.without_contact.count,
        stale_products: imported_products.where(source_synced_at: ...STALE_AFTER.ago).count,
        last_synced_at: imported_products.maximum(:source_synced_at)
      }

      @platforms = source_platforms.map do |platform|
        {
          platform: platform,
          storefronts: imported_storefronts.where(source_platform: platform).count,
          products: imported_products.where(source_platform: platform).count,
          reviews: imported_reviews.where(source_platform: platform).count,
          last_synced_at: imported_products.where(source_platform: platform).maximum(:source_synced_at)
        }
      end

      @recent_storefronts = imported_storefronts
        .order(source_synced_at: :desc, created_at: :desc)
        .limit(6)
      @recent_products = imported_products
        .includes(:commerce_storefront, :commerce_merchant)
        .order(source_synced_at: :desc, created_at: :desc)
        .limit(8)
      @stores_without_contact = imported_storefronts
        .without_contact
        .order(source_synced_at: :desc, created_at: :desc)
        .limit(5)
      @stale_products = imported_products
        .where(source_synced_at: ...STALE_AFTER.ago)
        .order(:source_synced_at)
        .limit(5)
    end

    # The platform-owned merchant that holds every imported catalog. Creating
    # it is a one-off ops step; it lives here so it does not need a shell.
    def create_system_merchant
      merchant = CommerceMerchant.system_merchant
      log_admin_action("system_merchant_ensured", merchant, { merchant_id: merchant.merchant_id })
      redirect_to admin_imports_path,
        notice: "Platform merchant #{merchant.display_name} (#{merchant.merchant_id}) is ready to own imported stores."
    end

    # ── Imported source stores ───────────────────────────────────────────

    def storefronts
      @storefronts = paginate(imported_storefronts_scope)
      @platforms = source_platforms
      @kinds = CommerceStorefront.imported.distinct.pluck(:source_kind).compact.sort
      @imported_count = CommerceStorefront.imported.count
    end

    def show_storefront
      @products = @storefront.commerce_products
        .includes(:commerce_merchant)
        .order(created_at: :desc)
        .limit(20)
      @product_count = @storefront.commerce_products.count
      @reviews = CommerceReview
        .for_merchant(@storefront.commerce_merchant_id)
        .imported
        .order(created_at: :desc)
        .limit(5)
      @reviews_count = CommerceReview
        .for_merchant(@storefront.commerce_merchant_id)
        .imported
        .count
    end

    def update_storefront
      if @storefront.update(storefront_params)
        log_admin_action("update_imported_storefront", @storefront.storefront_id, storefront_params.to_h)
        redirect_to admin_import_storefront_path(@storefront), notice: "Store updated."
      else
        flash.now[:alert] = "Could not save: #{@storefront.errors.full_messages.to_sentence}"
        show_storefront
        render :show_storefront, status: :unprocessable_entity
      end
    end

    # ── Imported listings ────────────────────────────────────────────────

    def products
      @products = paginate(imported_products_scope)
      @platforms = source_platforms
      @imported_count = CommerceProduct.imported.count
    end

    def show_product
      @skus = @product.commerce_skus.order(:created_at)
      @reviews = @product.commerce_reviews.order(created_at: :desc).limit(50)
      @source = @product.source_payload.is_a?(Hash) ? @product.source_payload : {}
    end

    def update_product
      if @product.update(product_params)
        log_admin_action("update_imported_product", @product.product_id, product_params.to_h)
        redirect_to admin_import_product_path(@product), notice: "Listing updated."
      else
        flash.now[:alert] = "Could not save: #{@product.errors.full_messages.to_sentence}"
        show_product
        render :show_product, status: :unprocessable_entity
      end
    end

    # ── Imported reviews ─────────────────────────────────────────────────

    def update_review
      if @review.update(review_params)
        log_admin_action("update_imported_review", @review.review_id, review_params.to_h)
        redirect_back fallback_location: admin_import_product_path(@review.commerce_product_id),
          notice: "Review updated."
      else
        redirect_back fallback_location: admin_imports_path,
          alert: "Could not update review: #{@review.errors.full_messages.to_sentence}"
      end
    end

    private

    def imported_storefronts_scope
      scope = CommerceStorefront.imported
        .includes(:commerce_merchant)
        .order(source_synced_at: :desc, created_at: :desc)
      scope = scope.where(source_platform: params[:platform]) if params[:platform].present?
      scope = scope.where(source_kind: params[:kind]) if params[:kind].present?
      scope = filter_by_query(scope, params[:query], %w[display_name source_id slug])
      scope
    end

    def imported_products_scope
      scope = CommerceProduct.imported
        .includes(:commerce_storefront, :commerce_merchant, :commerce_skus)
        .order(source_synced_at: :desc, created_at: :desc)
      scope = scope.where(source_platform: params[:platform]) if params[:platform].present?
      scope = scope.where(status: params[:status]) if params[:status].present?
      scope = filter_by_query(scope, params[:query], %w[title source_id])
      scope
    end

    # Case-insensitive search across the given columns. Bound parameters only —
    # the query text never reaches the SQL string.
    def filter_by_query(scope, query, columns)
      term = query.to_s.strip.downcase
      return scope if term.blank?

      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
      conditions = columns.map { |column| "LOWER(#{column}) LIKE :pattern" }.join(" OR ")
      scope.where(conditions, pattern: pattern)
    end

    def source_platforms
      (CommerceProduct.imported.distinct.pluck(:source_platform) +
        CommerceStorefront.imported.distinct.pluck(:source_platform)).compact.uniq.sort
    end

    def set_storefront
      @storefront = CommerceStorefront.imported.find(params[:id])
    end

    def set_product
      @product = CommerceProduct.imported.find(params[:id])
    end

    def set_review
      @review = CommerceReview.imported.find(params[:id])
    end

    def storefront_params
      params.require(:commerce_storefront).permit(
        :display_name, :about, :description, :status, :featured, :store_type,
        :accent_color, :contact_phone, :contact_email, :contact_website,
        :contact_address
      )
    end

    def product_params
      params.require(:commerce_product).permit(:status, :featured)
    end

    def review_params
      params.require(:commerce_review).permit(:status)
    end

    def require_view_imports!
      require_admin_permission!(:view_imports)
    end

    def require_manage_imports!
      require_admin_permission!(:manage_imports)
    end
  end
end
