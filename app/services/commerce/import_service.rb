# frozen_string_literal: true

module Commerce
  # Upserts externally-sourced catalog data (Jumia, Konga, ...) into the
  # Tween storefront.
  #
  # Every imported product keeps a pointer back to where it came from
  # (`source_platform` + `source_id`) which doubles as the natural key for
  # re-imports, so a scheduled sync updates the existing listing instead of
  # creating a duplicate. Reviews follow the same rule with
  # (`source_platform` + `source_review_id`).
  class ImportService
    PRODUCT_ATTRIBUTES = %w[
      title description short_description media_urls tags badges dimensions
      specifications warranty stock shipping identifiers variants
      source_category_path condition featured weight_grams seo_title
      seo_description status
    ].freeze

    SKU_ATTRIBUTES = %w[
      title price_cents currency inventory_status quantity_available image_url
    ].freeze

    #: Attributes that must land as JSONB objects (the storefront renders
    #: them directly, so a scalar or null in the payload must not corrupt them).
    JSON_ATTRIBUTES = %w[
      dimensions specifications warranty stock shipping identifiers variants
    ].freeze

    #: Attributes that are Postgres arrays.
    ARRAY_ATTRIBUTES = %w[tags badges source_category_path].freeze

    #: Imported catalogues live on the storefront experience — a priced shelf
    #: with cart and checkout. `marketplace` is the classified experience (buyer
    #: messages the seller, no checkout) and is for stores a person created, so
    #: nothing the importer writes may carry it.
    IMPORTED_STORE_TYPE = "ecommerce"

    STOREFRONT_ATTRIBUTES = %w[
      display_name about description logo_url banner_url accent_color
      store_type seo_title seo_description
    ].freeze

    # Source contact details are operator data (used to reach the seller), not
    # public storefront data.
    STOREFRONT_CONTACT_ATTRIBUTES = {
      "phone" => :contact_phone,
      "email" => :contact_email,
      "website" => :contact_website,
      "address" => :contact_address
    }.freeze

    SOURCE_KINDS = %w[seller brand].freeze

    # Imported reviewers are not Tween users, so their identity is namespaced
    # under a synthetic id derived from the source review. This keeps the
    # (buyer_user_id, commerce_product_id) uniqueness guarantee intact while
    # displaying the canonical name (or "Anonymous Buyer") to shoppers.
    def self.buyer_user_id_for(platform, source_review_id)
      "import:#{platform}:#{source_review_id}"
    end

    def self.call(merchant:, entries:, storefront_id: nil, category_id: nil, storefront: nil)
      new(
        merchant: merchant,
        entries: entries,
        storefront_id: storefront_id,
        category_id: category_id,
        storefront: storefront
      ).call
    end

    def initialize(merchant:, entries:, storefront_id: nil, category_id: nil, storefront: nil)
      @merchant = merchant
      @entries = entries
      @storefront_id = storefront_id
      @category_id = category_id
      @storefront_branding = as_hash(storefront)
    end

    def call
      Array(@entries).map { |entry| import_entry(as_hash(entry)) }
    end

    private

    def import_entry(entry)
      source = as_hash(entry["source"])
      platform = source["platform"].to_s.strip
      source_id = source["source_id"].to_s.strip
      raise ArgumentError, "source.platform is required" if platform.blank?
      raise ArgumentError, "source.source_id is required" if source_id.blank?

      product_attrs = as_hash(entry["product"])
      product = @merchant.commerce_products.find_or_initialize_by(
        source_platform: platform,
        source_id: source_id
      )
      action = product.new_record? ? "created" : "updated"

      sku_count = 0
      review_count = 0

      ActiveRecord::Base.transaction do
        assign_storefront(product, entry)
        assign_category(product, entry)

        product.assign_attributes(permitted_product_attributes(product_attrs))
        product.source_url = source["source_url"]
        product.source_payload = source
        product.source_category_path = source_category_path(entry)
        product.source_synced_at = Time.current
        # A mirrored listing carries a price and stock, so it belongs to the
        # storefront experience — cart, checkout, orders. Inheriting the store's
        # type instead let stores typed `marketplace` (the classified,
        # message-the-seller flow) drag their whole catalogue into a checkout-less
        # experience; the storefront's own type is fixed separately.
        product.store_type = product_attrs["store_type"].presence || IMPORTED_STORE_TYPE
        product.save!

        sku_count = sync_skus(product, Array(entry["skus"]))
        review_count = sync_reviews(product, Array(entry["reviews"]))

        product.recache_stats!
        product.commerce_storefront&.recache_stats!
      end

      {
        source_platform: platform,
        source_id: source_id,
        product_id: product.product_id,
        storefront_id: product.commerce_storefront&.storefront_id,
        action: action,
        skus: sku_count,
        reviews: review_count
      }
    rescue ActiveRecord::RecordInvalid, ArgumentError => e
      {
        source_platform: source["platform"],
        source_id: source["source_id"],
        action: "failed",
        error: e.message
      }
    end

    def permitted_product_attributes(attrs)
      attrs.slice(*PRODUCT_ATTRIBUTES).except("status").tap do |permitted|
        permitted["title"] = attrs["title"].to_s.strip if attrs["title"].present?
        permitted["status"] = attrs["status"] if attrs["status"].present?
        coerce_container_attributes(permitted)
      end
    end

    # JSONB columns and Postgres arrays are only ever written with the shape
    # they are declared as. A scraper that sends null, a string or a list
    # where an object is expected would otherwise persist something the
    # storefront then renders as a broken spec table.
    def coerce_container_attributes(attributes)
      JSON_ATTRIBUTES.each do |key|
        next unless attributes.key?(key)

        value = attributes[key]
        attributes[key] = value.is_a?(Hash) ? value.to_h : {}
      end

      ARRAY_ATTRIBUTES.each do |key|
        next unless attributes.key?(key)

        value = attributes[key]
        attributes[key] = Array(value).filter_map { |item| item.to_s.strip.presence }.uniq
      end
    end

    # The source's own taxonomy chain, kept on the listing as well as in the
    # payload: it is what an operator needs to re-map a branch later, and what
    # proves which marketplace branch a Tween category was derived from.
    # Read from the same place `category_path_for` reads, so provenance and
    # placement can never disagree about which chain the listing arrived with.
    def source_category_path(entry)
      names = category_path_for(entry)
      return names if names.present?

      source = as_hash(entry["source"])
      Array(source["category_slugs"]).filter_map { |slug| slug.to_s.strip.presence }
    end

    def assign_storefront(product, entry)
      # Per-entry branding wins over the batch-level storefront descriptor.
      branding = as_hash(entry["storefront"]).presence || @storefront_branding
      storefront_ref = entry["storefront_id"].presence || @storefront_id.presence

      if storefront_ref.present?
        product.commerce_storefront ||= @merchant.commerce_storefronts.find_by!(storefront_id: storefront_ref)
        apply_storefront_branding(product.commerce_storefront, branding)
      elsif as_hash(branding)["display_name"].blank?
        # Branding that names nothing goes to the merchant's default store.
        product.commerce_storefront ||= default_storefront
      else
        product.commerce_storefront ||= find_or_create_storefront(branding)
        apply_storefront_branding(product.commerce_storefront, branding)
      end
    end

    # Marketplaces get their own store so branding and browsing stay coherent
    # ("Jumia on Tween" vs "Konga on Tween") instead of every imported catalog
    # collapsing into the merchant's first store.
    def find_or_create_storefront(branding)
      # A store is keyed by slug, and a payload that names a store without
      # slugging it still names *a* store: derive the slug from the name rather
      # than letting the branding fall through onto the merchant's first store.
      # That fallthrough is how a seller's name and blurb once landed on the
      # platform's "Konga on Tween", and because a product keeps whichever
      # storefront it already has, every later import inherited the mistake.
      slug = branding["slug"].presence || branding["display_name"].to_s.parameterize.presence
      return default_storefront if slug.blank?

      @merchant.commerce_storefronts.find_or_create_by!(slug: slug) do |sf|
        sf.display_name = branding["display_name"].presence || slug.titleize
        sf.store_type = IMPORTED_STORE_TYPE
        sf.status = "published"
      end
    end

    def default_storefront
      @merchant.commerce_storefronts.first_or_create! do |sf|
        sf.display_name = @merchant.display_name
        sf.status = "published"
        sf.store_type = IMPORTED_STORE_TYPE
      end
    end

    def apply_storefront_branding(storefront, branding)
      return if branding.blank?

      storefront.assign_attributes(branding.slice(*STOREFRONT_ATTRIBUTES))
      # A re-import re-sends the storefront's branding, and older scrapers typed
      # source sellers `marketplace`. Pinning the type here keeps a stale payload
      # from re-classifying an already-corrected store.
      storefront.store_type = IMPORTED_STORE_TYPE
      apply_storefront_provenance(storefront, as_hash(branding["source"]))
      apply_storefront_contact(storefront, as_hash(branding["contact"]))
      storefront.status = "published" if storefront.status.blank? || storefront.status == "draft"
      storefront.save! if storefront.changed?
    end

    def apply_storefront_provenance(storefront, source)
      return if source.blank?

      kind = source["kind"].to_s
      storefront.source_platform = source["platform"].presence || storefront.source_platform
      storefront.source_kind = kind if SOURCE_KINDS.include?(kind)
      storefront.source_id = source["source_id"].presence || storefront.source_id
      storefront.source_url = source["source_url"].presence || storefront.source_url
      storefront.source_payload = source
      storefront.source_synced_at = Time.current
    end

    def apply_storefront_contact(storefront, contact)
      present = contact.slice(*STOREFRONT_CONTACT_ATTRIBUTES.keys)
      return if present.blank?

      STOREFRONT_CONTACT_ATTRIBUTES.each do |key, column|
        next unless contact.key?(key)

        storefront.public_send("#{column}=", contact[key].presence)
      end
      storefront.social_links = as_hash(contact["social_links"]) if contact.key?("social_links")
    end

    def assign_category(product, entry)
      category_ref = entry["category_id"].presence || @category_id.presence
      if category_ref.present?
        product.commerce_category = ::CommerceCategory.find_by!(category_id: category_ref)
        return
      end

      # An imported marketplace listing arrives with a chain of category
      # names rather than one of our ids. Resolving it is what makes the
      # listing browsable: the storefront filters products by category_id.
      Commerce::CategoryResolver.apply_to(product, category_path_for(entry))
    end

    # The category chain the scraper published, read from wherever the payload
    # actually carries it.
    #
    # The contract puts it at the top of the entry; one version of the scraper
    # sent it inside `product` instead, and the very first payloads carried
    # only the flat name pair. All four shapes are accepted, because reading
    # just one of them is how a whole catalog arrives with no category at all —
    # imported, and invisible to every category browse.
    def category_path_for(entry)
      candidates = [
        as_hash(entry["category"])["path"],
        as_hash(as_hash(entry["product"])["category"])["path"],
        as_hash(entry["source"])["category_path"],
        [ entry["parent_category_name"], entry["category_name"] ]
      ]
      found = candidates.find { |path| Array(path).compact_blank.present? }

      Array(found).compact_blank.map { |name| name.to_s.strip }.reject(&:empty?)
    end

    def sync_skus(product, skus)
      seen = []

      skus.each do |raw|
        sku_attrs = as_hash(raw)
        source_sku_id = sku_attrs["source_sku_id"].presence || sku_attrs["sku_id"].presence || sku_attrs["title"].to_s

        sku = product.commerce_skus.to_a.find do |candidate|
          as_hash(candidate.properties)["source_sku_id"].presence == source_sku_id
        end
        sku ||= product.commerce_skus.find { |candidate| candidate.title == sku_attrs["title"] }
        sku ||= product.commerce_skus.build

        sku.assign_attributes(sku_attrs.slice(*SKU_ATTRIBUTES))
        sku.image_url = sku_attrs["image"].presence || sku_attrs["image_url"].presence
        sku.currency = sku_attrs["currency"].presence || "NGN"
        sku.inventory_status = sku_attrs["inventory_status"].presence || "in_stock"
        sku.properties = as_hash(sku_attrs["properties"]).merge("source_sku_id" => source_sku_id)
        sku.save!

        seen << sku.id
      end

      # Sources drop SKUs over time. Rather than destroy them (restricted by
      # existing carts/orders) mark the stragglers out of stock.
      product.commerce_skus.reload.each do |sku|
        next if seen.include?(sku.id)
        next if sku.inventory_status == "out_of_stock"

        sku.update!(inventory_status: "out_of_stock", quantity_available: 0)
      end

      seen.size
    end

    def sync_reviews(product, reviews)
      reviews.reduce(0) do |count, raw|
        review_attrs = as_hash(raw)
        source_review_id = review_attrs["source_review_id"].presence
        next count if source_review_id.blank?

        platform = product.source_platform
        review = ::CommerceReview.find_or_initialize_by(
          source_platform: platform,
          source_review_id: source_review_id
        )

        anonymous = ActiveModel::Type::Boolean.new.cast(review_attrs["is_anonymous"])
        review.assign_attributes(
          commerce_product: product,
          commerce_merchant: @merchant,
          buyer_user_id: self.class.buyer_user_id_for(platform, source_review_id),
          rating: review_attrs["rating"].to_i.clamp(1, 5),
          title: review_attrs["title"],
          body: review_attrs["body"],
          helpful_count: review_attrs["helpful_count"].to_i,
          status: "approved",
          imported: true,
          is_anonymous: anonymous,
          reviewer_display_name: display_name_for(review_attrs, anonymous),
          reviewer_handle: handle_for(review_attrs, anonymous),
          review_date: review_attrs["review_date"],
          source_payload: review_attrs
        )
        review.save!

        count + 1
      end
    end

    def display_name_for(attrs, anonymous)
      return "Anonymous Buyer" if anonymous

      attrs["reviewer_display_name"].presence || attrs["reviewer_handle"].presence || "Tween Shopper"
    end

    def handle_for(attrs, anonymous)
      return "Anonymous" if anonymous

      attrs["reviewer_handle"].presence || attrs["reviewer_display_name"].presence
    end

    def as_hash(value)
      return {} if value.blank?
      return value.to_unsafe_h if value.respond_to?(:to_unsafe_h)

      value.respond_to?(:to_h) ? value.to_h.stringify_keys : {}
    end
  end
end
