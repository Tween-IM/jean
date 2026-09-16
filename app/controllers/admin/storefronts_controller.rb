# frozen_string_literal: true

module Admin
  # Storefront management across the whole marketplace, not just the imported
  # catalogues: branding, contacts, visibility, and whether a store actually
  # has anything in it.
  #
  # Branding uploads go to the shared system bucket (`Commerce::AssetUploader`),
  # because the mirrored stores will never publish a logo of their own — an
  # operator either uploads one or the app draws a monogram.
  class StorefrontsController < BaseController
    STATUSES = %w[draft published suspended closed].freeze
    STORE_TYPES = %w[ecommerce marketplace].freeze
    BRANDING_ASSETS = { "logo" => "logo_url", "banner" => "banner_url" }.freeze

    before_action :require_view_storefronts!
    before_action :require_manage_storefronts!, only: [ :update, :enrich, :feature ]
    before_action :set_storefront, only: [ :show, :update, :enrich, :feature ]

    def index
      @stats = stats
      @storefronts = paginate(storefront_scope.includes(:commerce_merchant))
      @platforms = CommerceStorefront.where.not(source_platform: nil).distinct.pluck(:source_platform).compact.sort
      @merchants = CommerceMerchant.order(:display_name).limit(200)
      @statuses = STATUSES
      @store_types = STORE_TYPES
      @kinds = CommerceStorefront.where.not(source_kind: nil).distinct.pluck(:source_kind).compact.sort
    end

    def show
      @merchant = @storefront.commerce_merchant
      @products = @storefront.commerce_products.order(created_at: :desc).limit(20)
      @product_count = @storefront.commerce_products.count
      @orders = CommerceOrder.where(commerce_merchant_id: @merchant.id).order(created_at: :desc).limit(10)
      @order_count = CommerceOrder.where(commerce_merchant_id: @merchant.id).count
      @source = @storefront.source_payload.is_a?(Hash) ? @storefront.source_payload : {}
      @social_links = @storefront.social_links.is_a?(Hash) ? @storefront.social_links : {}
      @policies = @storefront.policies.is_a?(Hash) ? @storefront.policies : {}
      @contact_channels = contact_channels
    end

    def update
      attributes = storefront_params.to_h
      removals = BRANDING_ASSETS.values.select { |column| params.dig(:commerce_storefront, "remove_#{column}").present? }
      removals.each { |column| attributes[column] = nil }

      uploads = branding_uploads
      attributes = attributes.merge(uploads)

      if @storefront.update(attributes)
        log_admin_action("update_storefront", @storefront.storefront_id,
          attributes.except("logo_url", "banner_url").merge("uploaded" => uploads.keys, "cleared" => removals))
        redirect_to admin_storefront_path(@storefront), notice: "Store updated."
      else
        flash.now[:alert] = "Could not save: #{@storefront.errors.full_messages.to_sentence}"
        show
        render :show, status: :unprocessable_entity
      end
    rescue Commerce::AssetUploader::Error => e
      flash.now[:alert] = e.message
      show
      render :show, status: :unprocessable_entity
    end

    # Ask the source listings for branding the store itself never got. Only
    # fills blanks, so an operator upload survives.
    def enrich
      summary = Commerce::StorefrontBrandingBackfill.call(dry_run: false, only: @storefront)
      log_admin_action("enrich_storefront_branding", @storefront.storefront_id,
        filled: summary.stores_filled, banners: summary.banners, addresses: summary.addresses)

      if summary.stores_filled.positive?
        redirect_to admin_storefront_path(@storefront),
          notice: "Pulled branding from the source: #{summary.banners} banner(s), #{summary.addresses} address(es)."
      else
        redirect_to admin_storefront_path(@storefront),
          alert: "The source listings carry no branding this store is missing."
      end
    end

    def feature
      @storefront.update!(featured: !@storefront.featured)
      log_admin_action("feature_storefront", @storefront.storefront_id, featured: @storefront.featured)
      redirect_to admin_storefront_path(@storefront),
        notice: @storefront.featured ? "Store is now featured." : "Store is no longer featured."
    end

    private

    def set_storefront
      @storefront = CommerceStorefront.find(params[:id])
    end

    def branding_uploads
      uploader = Commerce::AssetUploader.new
      BRANDING_ASSETS.each_with_object({}) do |(param, column), result|
        file = params.dig(:commerce_storefront, param)
        next unless file.respond_to?(:read) && file.respond_to?(:content_type)

        result[column] = uploader.put(
          storefront: @storefront,
          asset: param,
          io: file,
          content_type: file.content_type,
          filename: file.original_filename
        )
      end
    end

    def contact_channels
      {
        "Phone" => @storefront.contact_phone,
        "Email" => @storefront.contact_email,
        "Website" => @storefront.contact_website,
        "Address" => @storefront.contact_address
      }.compact_blank
    end

    def storefront_scope
      scope = CommerceStorefront.all
      scope = scope.where("LOWER(display_name) LIKE :q OR LOWER(slug) LIKE :q OR LOWER(COALESCE(source_id, '')) LIKE :q",
        q: "%#{ActiveRecord::Base.sanitize_sql_like(params[:query].to_s.strip.downcase)}%") if params[:query].present?
      if params[:platform] == "own"
        scope = scope.where(source_platform: nil)
      elsif params[:platform].present?
        scope = scope.where(source_platform: params[:platform])
      end
      scope = scope.where(source_kind: params[:kind]) if params[:kind].present?
      scope = scope.where(status: params[:status]) if params[:status].present?
      scope = scope.where(store_type: params[:store_type]) if params[:store_type].present?
      scope = scope.where(featured: true) if params[:featured] == "1"
      scope = scope.where(commerce_merchant_id: params[:merchant]) if params[:merchant].present?
      if %w[system merchant].include?(params[:owner])
        system_merchant_ids = CommerceMerchant.system_owned.select(:id)
        scope = params[:owner] == "system" ? scope.where(commerce_merchant_id: system_merchant_ids) :
          scope.where.not(commerce_merchant_id: system_merchant_ids)
      end

      scope = case params[:missing]
      when "logo" then scope.where(logo_url: [ nil, "" ])
      when "banner" then scope.where(banner_url: [ nil, "" ])
      when "contact" then scope.without_contact
      when "products" then scope.where(product_count: [ nil, 0 ])
      else scope
      end

      case params[:sort]
      when "products" then scope.order(product_count: :desc, display_name: :asc)
      when "orders" then scope.order(order_count: :desc, display_name: :asc)
      when "newest" then scope.order(created_at: :desc)
      else scope.order(featured: :desc, display_name: :asc)
      end
    end

    def stats
      imported = CommerceStorefront.where.not(source_platform: nil)
      {
        total: CommerceStorefront.count,
        published: CommerceStorefront.where(status: "published").count,
        imported: imported.count,
        without_logo: imported.where(logo_url: [ nil, "" ]).count,
        without_banner: imported.where(banner_url: [ nil, "" ]).count,
        without_contact: imported.without_contact.count,
        featured: CommerceStorefront.where(featured: true).count
      }
    end

    def storefront_params
      params.require(:commerce_storefront).permit(
        :display_name, :about, :description, :status, :featured, :store_type,
        :accent_color, :contact_phone, :contact_email, :contact_website, :contact_address,
        :logo_url, :banner_url, :seo_title, :seo_description, :social_share_enabled,
        :allow_promotion
      )
    end

    def require_view_storefronts!
      require_admin_permission!(:view_storefronts)
    end

    def require_manage_storefronts!
      require_admin_permission!(:manage_storefronts)
    end
  end
end
