# frozen_string_literal: true

class Api::V1::Commerce::ProductsController < Api::V1::Commerce::BaseController
  #: What a listing costs — its cheapest SKU. Read as a correlated subquery
  #: rather than a join so a listing with several SKUs stays one row instead of
  #: being duplicated by the join (which is also what forced the old price sort
  #: into a DISTINCT that PostgreSQL rejects alongside ORDER BY).
  MIN_PRICE_SQL = "(SELECT MIN(commerce_skus.price_cents) FROM commerce_skus " \
                  "WHERE commerce_skus.commerce_product_id = commerce_products.id)".freeze

  #: How each sort is ordered and paged. `key` is both the ordering expression
  #: and what the cursor is built from, so the two can never disagree.
  #: `cursor_value` reads the same value back off a loaded record.
  #: `computed` marks a sort whose key is an expression rather than a plain
  #: column. `with_available_stock` is a SELECT DISTINCT (the SKU join
  #: duplicates rows) and PostgreSQL requires every ORDER BY expression of a
  #: DISTINCT query to be in the select list, so those keys are aliased in as
  #: `sort_key` and the ordering refers to the alias.
  SORTS = {
    "newest" => {
      key: "commerce_products.created_at",
      direction: :desc,
      cursor_value: ->(product) { product.created_at.utc.iso8601(6) }
    },
    "popular" => {
      key: "COALESCE(commerce_products.sales_count, 0)",
      direction: :desc,
      computed: true,
      cursor_value: ->(product) { product.sort_key.to_i }
    },
    "rating" => {
      key: "COALESCE(commerce_products.rating_average, 0)",
      direction: :desc,
      computed: true,
      cursor_value: ->(product) { product.sort_key.to_f }
    },
    "price_asc" => {
      key: MIN_PRICE_SQL,
      direction: :asc,
      computed: true,
      cursor_value: ->(product) { product.sort_key.to_i }
    },
    "price_desc" => {
      key: MIN_PRICE_SQL,
      direction: :desc,
      computed: true,
      cursor_value: ->(product) { product.sort_key.to_i }
    }
  }.freeze

  #: Newest first, which is what the storefront opens on.
  DEFAULT_SORT = {
    key: "commerce_products.created_at",
    direction: :desc,
    cursor_value: ->(product) { product.created_at.utc.iso8601(6) }
  }.freeze

  def index
    require_scope("commerce:read")

    products = ::CommerceProduct.active.with_available_stock.includes(:commerce_merchant, :commerce_category, :commerce_storefront).preload(:commerce_skus)
    products = products.joins(:commerce_merchant).where(commerce_merchants: { merchant_id: params[:merchant_id] }) if params[:merchant_id].present?
    products = products.where(commerce_storefront_id: ::CommerceStorefront.where(storefront_id: params[:storefront_id]).select(:id)) if params[:storefront_id].present?

    if params[:category_id].present?
      branch_ids = category_branch_ids(params[:category_id])
      if branch_ids.empty?
        render json: { products: [], meta: { total: 0 }, next_cursor: nil }
        return
      end
      # A listing records the top of its chain as its category and its leaf as
      # its subcategory, so a branch has to be matched on either side —
      # otherwise browsing a subcategory finds nothing.
      products = products.where(category_id: branch_ids).or(products.where(subcategory_id: branch_ids))
    end

    if params[:min_price].present?
      products = products.where("#{MIN_PRICE_SQL} >= ?", params[:min_price].to_i)
    end

    if params[:max_price].present?
      products = products.where("#{MIN_PRICE_SQL} <= ?", params[:max_price].to_i)
    end

    if params[:condition].present?
      products = products.where(condition: params[:condition])
    end

    if params[:search].present?
      query = "%#{params[:search].downcase}%"
      products = products.where("LOWER(title) LIKE ? OR LOWER(description) LIKE ? OR ? = ANY(tags)", query, query, params[:search].downcase)
    end

    total_count = products.count

    sort = SORTS[params[:sort].to_s] || DEFAULT_SORT
    order_key = sort[:key]
    if sort[:computed]
      products = products.select("commerce_products.*, (#{sort[:key]}) AS sort_key")
      order_key = "sort_key"
    end
    products = products.order(Arel.sql("#{order_key} #{sort[:direction] == :asc ? 'ASC' : 'DESC'}"), id: sort[:direction])
    products, next_cursor = page_of(products, sort)

    render json: {
      products: products.map { |p| product_json(p, detail: :public) },
      meta: { total: total_count },
      next_cursor: next_cursor
    }
  end

  def featured
    require_scope("commerce:read")

    products = ::CommerceProduct.active.with_available_stock.where(featured: true).includes(:commerce_merchant).order(created_at: :desc).limit(20)
    render json: { products: products.map { |p| product_json(p, detail: :public) } }
  end

  def trending
    require_scope("commerce:read")

    products = ::CommerceProduct.active.with_available_stock.order(sales_count: :desc, view_count: :desc).includes(:commerce_merchant).limit(20)
    render json: { products: products.map { |p| product_json(p, detail: :public) } }
  end

  def search
    require_scope("commerce:read")

    query = params[:q].to_s.strip
    category_id = params[:category_id]
    sort = params[:sort]

    if query.length < 2 && category_id.blank?
      render json: { products: [], meta: { total: 0 } }
      return
    end

    scope = ::CommerceProduct.active.with_available_stock.includes(:commerce_merchant).preload(:commerce_skus)

    if query.length >= 2
      search_query = "%#{query.downcase}%"
      scope = scope.where(
        "LOWER(title) LIKE ? OR LOWER(description) LIKE ? OR ? = ANY(tags)",
        search_query, search_query, query.downcase
      )
    end

    if category_id.present?
      scope = scope.where(
        category_id: ::CommerceCategory.where(category_id: category_id).select(:id)
      )
    end

    if params[:min_price].present? || params[:max_price].present?
      scope = scope.joins(:commerce_skus)
      scope = scope.where("commerce_skus.price_cents >= ?", params[:min_price].to_i) if params[:min_price].present?
      scope = scope.where("commerce_skus.price_cents <= ?", params[:max_price].to_i) if params[:max_price].present?
    end

    scope = scope.where(condition: params[:condition].to_s) if params[:condition].present?

    scope = case sort
            when "price_asc" then scope.joins(:commerce_skus).order("commerce_skus.price_cents ASC")
            when "price_desc" then scope.joins(:commerce_skus).order("commerce_skus.price_cents DESC")
            when "newest" then scope.order(created_at: :desc)
            when "popular" then scope.order(sales_count: :desc)
            when "rating" then scope.order(rating_average: :desc)
            else scope.order(created_at: :desc)
            end

    total_count = scope.count
    products = scope.limit(limit_param(default: 20, max: 50))

    render json: {
      products: products.map { |p| product_json(p, detail: :public) },
      meta: { total: total_count, query: query }
    }
  end

  def show
    require_scope("commerce:read")

    product = find_product
    product.increment!(:view_count)

    related = ::CommerceProduct.active.with_available_stock
      .where.not(product_id: product.product_id)
      .where(category_id: product.category_id)
      .limit(4)

    render json: {
      product: product_json(product, detail: :full),
      review_eligibility: Commerce::ReviewEligibilityService.can_review?(
        buyer_user_id: @current_user.matrix_user_id,
        product: product
      ),
      reviews: product.commerce_reviews.approved.limit(10).map { |r| review_json(r) },
      related_products: related.map { |p| product_json(p, detail: :public) }
    }
  end

  def create
    require_scope("commerce:merchant")

    merchant = find_merchant
    return if ensure_merchant_owner(merchant)

    permitted = product_params
    permitted[:title] = permitted.delete(:name) if permitted[:name].present?

    product = merchant.commerce_products.new(permitted)
    assign_storefront(product)
    assign_category(product)

    if product.save
      begin
        ActiveRecord::Base.transaction do
          create_skus(product)
          ensure_default_sku(product)
          link_shipping_profiles(product)
        end
        product.commerce_storefront&.recache_stats!
        render json: { product: product_json(product.reload, detail: :full) }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        product.destroy
        render json: { error: "validation_failed", message: e.message }, status: :unprocessable_entity
      end
    else
      render_errors(product)
    end
  end

  def update
    require_scope("commerce:merchant")

    product = find_product
    return if ensure_merchant_owner(product.commerce_merchant)

    assign_storefront(product)
    assign_category(product)

    permitted = product_params
    permitted[:title] = permitted.delete(:name) if permitted[:name].present?

    if product.update(permitted)
      update_skus(product) if params[:skus].present?
      link_shipping_profiles(product) if params[:shipping_profile_ids].present?
      product.commerce_storefront&.recache_stats!
      render json: { product: product_json(product.reload, detail: :full) }
    else
      render_errors(product)
    end
  end

  def destroy
    require_scope("commerce:merchant")

    product = find_product
    return if ensure_merchant_owner(product.commerce_merchant)

    product.update!(status: "archived")
    product.commerce_storefront&.recache_stats!
    render json: { product: product_json(product, detail: :public) }
  end

  private

  def product_params
    params.require(:product).permit(
      :title, :name, :description, :status, :condition, :featured,
      :weight_grams, :seo_title, :seo_description, :store_type,
      media_urls: [], tags: [], dimensions: {}
    )
  end

  def assign_storefront(product)
    if params[:storefront_id].present?
      product.commerce_storefront = product.commerce_merchant.commerce_storefronts.find_by!(storefront_id: params[:storefront_id])
    else
      # Products always belong to a store. Auto-create a marketplace store if
      # the merchant doesn't have one yet (individual / classified sellers).
      product.commerce_storefront = product.commerce_merchant.commerce_storefronts.first_or_create! do |sf|
        sf.display_name = product.commerce_merchant.display_name
        sf.status = "published"
        sf.store_type = "marketplace"
      end
    end
    # A product inherits the store's experience type when one isn't explicit.
    product.store_type ||= product.commerce_storefront.store_type
  end

  def assign_category(product)
    return if params[:category_id].blank?

    product.commerce_category = ::CommerceCategory.find_by!(category_id: params[:category_id])
  end

  def create_skus(product)
    Array(params[:skus]).each do |sku_params|
      sku_hash = sku_params.respond_to?(:to_unsafe_h) ? sku_params.to_unsafe_h : sku_params
      permitted_sku = ActionController::Parameters.new(sku_hash).permit(
        :title, :price_cents, :currency, :inventory_status, :quantity_available, properties: {}
      )
      permitted_sku[:currency] ||= 'NGN'
      product.commerce_skus.create!(permitted_sku)
    end
  end

  # Fast Lane listings carry price inside dimensions.listing rather than a
  # skus array. Without at least one SKU a product has no price_range and is
  # filtered out of the marketplace (`with_available_stock` joins SKUs), so
  # synthesize a default SKU from the listing price when none were provided.
  def ensure_default_sku(product)
    return if product.commerce_skus.any?

    listing = product.dimensions.to_h.dig("listing")
    return if listing.blank?

    price_cents = listing["price"]
    return if price_cents.blank?

    product.commerce_skus.create!(
      title: "Default",
      price_cents: price_cents,
      currency: listing["currency"] || 'NGN',
      inventory_status: "in_stock"
    )
  end

  def update_skus(product)
    Array(params[:skus]).each do |sku_params|
      sku_hash = sku_params.respond_to?(:to_unsafe_h) ? sku_params.to_unsafe_h : sku_params
      if sku_hash["sku_id"].present?
        permitted = ActionController::Parameters.new(sku_hash.except("sku_id")).permit(:title, :price_cents, :currency, :inventory_status, :quantity_available, properties: {})
        permitted[:currency] ||= 'NGN'
        sku = product.commerce_skus.find_by(sku_id: sku_hash["sku_id"])
        sku&.update!(permitted)
      else
        permitted_sku = ActionController::Parameters.new(sku_hash).permit(
          :title, :price_cents, :currency, :inventory_status, :quantity_available, properties: {}
        )
        permitted_sku[:currency] ||= 'NGN'
        product.commerce_skus.create!(permitted_sku)
      end
    end
  end

  def link_shipping_profiles(product)
    product.commerce_product_shipping.destroy_all
    Array(params[:shipping_profile_ids]).each do |profile_id|
      profile = product.commerce_merchant.commerce_shipping_profiles.find_by(shipping_profile_id: profile_id)
      product.commerce_product_shipping.create!(commerce_shipping_profile: profile) if profile
    end
  end

  def limit_param(default:, max:)
    [ (params[:limit] || default).to_i, max ].min
  end

  # ── Paging ──────────────────────────────────────────────────────────

  # One page of listings, plus the cursor that asks for the next one.
  #
  # The cursor is a keyset, not an offset: it names the exact row the previous
  # page ended on, so a listing published while somebody is scrolling can never
  # push a page down and make them miss one, or be shown twice. A page is only
  # answered with a cursor when there is more behind it.
  def page_of(products, sort)
    limit = limit_param(default: 20, max: 100)

    if (values = decode_product_cursor(params[:cursor]))
      key, last_id = values
      comparison = sort[:direction] == :asc ? ">" : "<"
      products = products.where(
        "(#{sort[:key]}, commerce_products.id) #{comparison} (?, ?)",
        key, last_id
      )
    end

    rows = products.limit(limit + 1).to_a
    return [ rows, nil ] unless rows.size > limit

    page = rows.first(limit)
    [ page, encode_product_cursor(sort[:cursor_value].call(page.last), page.last.id) ]
  end

  def encode_product_cursor(key, id)
    Base64.urlsafe_encode64({ key: key, id: id }.to_json)
  end

  # A cursor we cannot read is treated as "start again" rather than an error:
  # the worst it can cost a reader is the top of the list.
  def decode_product_cursor(cursor)
    return nil if cursor.blank?

    decoded = JSON.parse(Base64.urlsafe_decode64(cursor.to_s))
    key = decoded["key"]
    id = decoded["id"]
    return nil if key.nil? || id.nil?

    [ key, id ]
  rescue StandardError
    nil
  end

  # ── Categories ──────────────────────────────────────────────────────

  # The category the buyer picked, plus everything filed under it. Browsing a
  # top-level branch has to include its children: a product records the top of
  # its chain as its category, so a parent with four hundred listings under its
  # subcategories would otherwise look empty.
  def category_branch_ids(category_id)
    ::CommerceCategory.connection.select_values(
      ::CommerceCategory.sanitize_sql_array([ <<~SQL, category_id ])
        WITH RECURSIVE branch AS (
          SELECT id, parent_id FROM commerce_categories WHERE category_id = ?
          UNION
          SELECT c.id, c.parent_id FROM commerce_categories c JOIN branch b ON c.parent_id = b.id
        )
        SELECT id FROM branch
      SQL
    ).map(&:to_i)
  end
end
