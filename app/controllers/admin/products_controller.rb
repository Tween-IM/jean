# frozen_string_literal: true

module Admin
  # The catalogue desk: every listing on the platform (imported or merchant
  # created), with the fields an operator actually corrects — status,
  # category, copy, media — plus the SKUs that carry price and stock.
  class ProductsController < BaseController
    STATUSES = %w[active draft archived rejected].freeze
    SORTS = %w[newest oldest sales rating price].freeze

    before_action :require_view_catalog!
    before_action :require_manage_catalog!, only: [ :update, :media ]
    before_action :set_product, only: [ :show, :update, :media ]

    def index
      @stats = stats
      @products = paginate(product_scope.includes(:commerce_storefront, :commerce_merchant, :commerce_skus))
      @platforms = CommerceProduct.where.not(source_platform: nil).distinct.pluck(:source_platform).compact.sort
      @storefronts = CommerceStorefront.order(:display_name).limit(500)
      @merchants = CommerceMerchant.order(:display_name).limit(200)
      @categories = CommerceCategory.order(:name).limit(1000)
      @statuses = STATUSES
    end

    def show
      @skus = @product.commerce_skus.order(:created_at)
      @reviews = @product.commerce_reviews.order(created_at: :desc).limit(25)
      @source = @product.source_payload.is_a?(Hash) ? @product.source_payload : {}
      @storefront = @product.commerce_storefront
      @category = CommerceCategory.find_by(id: @product.category_id)
      @subcategory = CommerceCategory.find_by(id: @product.subcategory_id)
      @categories = CommerceCategory.order(:name).limit(1000)
      @media = Array(@product.media_urls)
      @specifications = @product.specifications.is_a?(Hash) ? @product.specifications : {}
      @identifiers = @product.identifiers.is_a?(Hash) ? @product.identifiers : {}
    end

    def update
      if @product.update(product_params)
        log_admin_action("update_product", @product.product_id, product_params.to_h.except("description"))
        redirect_to admin_product_path(@product), notice: "Listing updated."
      else
        flash.now[:alert] = "Could not save: #{@product.errors.full_messages.to_sentence}"
        show
        render :show, status: :unprocessable_entity
      end
    end

    # Adds an image the source never published, or drops one that 404s.
    def media
      if params[:remove_url].present?
        remaining = Array(@product.media_urls) - [ params[:remove_url].to_s ]
        @product.update!(media_urls: remaining)
        log_admin_action("remove_product_media", @product.product_id, url: params[:remove_url])
        return redirect_to admin_product_path(@product), notice: "Image removed."
      end

      file = params[:image]
      unless file.respond_to?(:read) && file.respond_to?(:content_type)
        return redirect_to admin_product_path(@product), alert: "Choose an image to upload."
      end

      url = Commerce::AssetUploader.new.put_media(
        product: @product, io: file, content_type: file.content_type, filename: file.original_filename
      )

      @product.update!(media_urls: Array(@product.media_urls) + [ url ])
      log_admin_action("add_product_media", @product.product_id, url: url)
      redirect_to admin_product_path(@product), notice: "Image added."
    rescue Commerce::AssetUploader::Error => e
      redirect_to admin_product_path(@product), alert: e.message
    end

    private

    def set_product
      @product = CommerceProduct.includes(:commerce_storefront, :commerce_merchant).find(params[:id])
    end

    def product_scope
      scope = CommerceProduct.all
      if params[:query].present?
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(params[:query].to_s.strip.downcase)}%"
        scope = scope.where(
          "LOWER(title) LIKE :pattern OR LOWER(product_id) LIKE :pattern OR LOWER(COALESCE(source_id, '')) LIKE :pattern",
          pattern: pattern
        )
      end
      scope = scope.where(source_platform: params[:platform]) if params[:platform].present?
      scope = scope.where(status: params[:status]) if params[:status].present?
      scope = scope.where(commerce_storefront_id: params[:storefront]) if params[:storefront].present?
      scope = scope.where(commerce_merchant_id: params[:merchant]) if params[:merchant].present?
      scope = scope.where(condition: params[:condition]) if params[:condition].present?
      scope = scope.where(featured: true) if params[:featured] == "1"
      scope = scope.where(source_platform: nil) if params[:origin] == "own"
      scope = scope.where.not(source_platform: nil) if params[:origin] == "imported"
      scope = category_filter(scope)

      scope = case params[:missing]
      when "media" then scope.where("media_urls IS NULL OR media_urls = '[]'::jsonb")
      when "category" then scope.where(category_id: nil)
      when "sku" then scope.where.not(id: CommerceSku.select(:commerce_product_id))
      else scope
      end

      case params[:sort]
      when "oldest" then scope.order(created_at: :asc)
      when "sales" then scope.order(sales_count: :desc, created_at: :desc)
      when "rating" then scope.order(Arel.sql("rating_average DESC NULLS LAST"), created_at: :desc)
      when "price" then scope.order(Arel.sql("(SELECT MIN(price_cents) FROM commerce_skus WHERE commerce_skus.commerce_product_id = commerce_products.id) ASC NULLS LAST"))
      else scope.order(created_at: :desc)
      end
    end

    # A category filter matches the branch: listings filed on the parent or any
    # of its children should both show up.
    def category_filter(scope)
      return scope if params[:category].blank?
      return scope.where(category_id: nil) if params[:category] == "none"

      branch_ids = [ params[:category] ] + CommerceCategory.where(parent_id: params[:category]).pluck(:id)
      scope.where("category_id IN (:ids) OR subcategory_id IN (:ids)", ids: branch_ids)
    end

    def stats
      base = CommerceProduct.all
      {
        total: base.count,
        active: base.where(status: "active").count,
        imported: base.where.not(source_platform: nil).count,
        archived: base.where(status: "archived").count,
        draft: base.where(status: "draft").count,
        missing_media: base.where("media_urls IS NULL OR media_urls = '[]'::jsonb").count,
        uncategorised: base.where(category_id: nil).count,
        without_sku: base.where.not(id: CommerceSku.select(:commerce_product_id)).count
      }
    end

    def product_params
      permitted = params.require(:commerce_product).permit(
        :title, :short_description, :description, :status, :featured, :condition,
        :warranty, :category_id, :subcategory_id, :seo_title, :seo_description,
        :stock, :weight_grams
      )
      permitted[:tags] = params.dig(:commerce_product, :tags).to_s.split(",").map(&:strip).reject(&:blank?) if params.dig(:commerce_product, :tags)
      permitted
    end

    def require_view_catalog!
      require_admin_permission!(:view_catalog)
    end

    def require_manage_catalog!
      require_admin_permission!(:manage_catalog)
    end
  end
end
