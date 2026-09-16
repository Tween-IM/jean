# frozen_string_literal: true

module Commerce
  # Re-files imported listings that landed on a marketplace's catch-all store
  # onto the store that actually sells them.
  #
  # The sweep pushes listings it has not enriched yet — no brand, no captured
  # source store, but a seller name in the payload — and those all resolved to
  # "<platform> on Tween". One storefront ended up holding hundreds of unrelated
  # sellers, and because a product keeps whichever storefront it already has,
  # re-importing never moved them.
  #
  # Targeting mirrors the importer's own grouping: a listing that names a brand
  # belongs to the brand store, otherwise to its seller. Branding is whatever the
  # listing's record published — banner, location, the seller's own slug — and
  # nothing at all where Konga published nothing, so a store without a logo is
  # drawn as a monogram rather than handed a made-up mark.
  class ListingAttribution
    #: Slugs the importer gives a marketplace's own store.
    CATCH_ALL_SLUG = "%-on-tween"

    Summary = Struct.new(
      :listings_moved, :stores_created, :stores_enriched, :without_store,
      keyword_init: true
    ) do
      def to_s
        "listings moved: #{listings_moved} | stores created: #{stores_created} | " \
          "stores enriched: #{stores_enriched} | listings naming no store: #{without_store}"
      end
    end

    def initialize(dry_run: true, logger: Rails.logger)
      @dry_run = dry_run
      @logger = logger
      @stores_by_slug = {}
      @missing_slugs = Set.new
      @summary = Summary.new(
        listings_moved: 0, stores_created: 0, stores_enriched: 0, without_store: 0
      )
    end

    def self.call(dry_run: true, logger: Rails.logger)
      new(dry_run: dry_run, logger: logger).call
    end

    def call
      candidates.find_each do |product|
        target = target_for(product)
        if target.nil?
          @summary.without_store += 1
          next
        end

        store = storefront_for(product, *target)
        if store == :would_create
          # Nothing is written in a dry run, but the listing is still one this
          # pass would move — that count is the whole point of the dry run.
          @summary.listings_moved += 1
          next
        end
        next if store.nil? || store.id == product.commerce_storefront_id

        @summary.listings_moved += 1
        next if @dry_run

        product.update_columns(
          commerce_storefront_id: store.id,
          store_type: Commerce::ImportService::IMPORTED_STORE_TYPE,
          updated_at: Time.current
        )
      end

      @summary
    end

    private

    #: Only listings on a marketplace's own store, and only imported ones: a
    #: store a person created is never touched.
    def candidates
      catch_all = CommerceStorefront.where("slug LIKE ?", CATCH_ALL_SLUG).select(:id)
      CommerceProduct.where(commerce_storefront_id: catch_all)
                     .where.not(source_platform: nil)
                     .includes(:commerce_merchant)
    end

    #: `[kind, name, record]` — the store this listing belongs to, or nil when
    #: the listing names neither a brand nor a seller.
    def target_for(product)
      payload = product.source_payload.is_a?(Hash) ? product.source_payload : {}
      brand = payload["brand"].to_s.strip
      return [ :brand, brand, {} ] if brand.present? && brand.parameterize.present?

      seller = payload["seller"].is_a?(Hash) ? payload["seller"] : {}
      name = (seller["name"].presence || payload["seller_name"].presence).to_s.strip
      return nil if name.blank? || name.parameterize.blank?

      [ :seller, name, seller ]
    end

    def storefront_for(product, kind, name, record)
      slug = kind == :brand ? name.parameterize : "#{name.parameterize}-#{product.source_platform}"
      return @stores_by_slug[slug] if @stores_by_slug.key?(slug)
      return nil if @missing_slugs.include?(slug)

      store = product.commerce_merchant.commerce_storefronts.find_by(slug: slug)
      created = store.nil?

      if created
        @summary.stores_created += 1
        if @dry_run
          @missing_slugs << slug
          return :would_create
        end
        store = product.commerce_merchant.commerce_storefronts.new(
          store_attributes(product, kind, name, record, slug)
        )
        store.save!
      elsif enrich(store, record)
        @summary.stores_enriched += 1
      end

      @stores_by_slug[slug] = store
    end

    def store_attributes(product, kind, name, record, slug)
      {
        # The slug is the key this pass looked the store up by, so it is set
        # rather than left to the model to derive from the display name.
        slug: slug,
        display_name: name.truncate(120),
        store_type: Commerce::ImportService::IMPORTED_STORE_TYPE,
        status: "published",
        banner_url: record["banner"],
        logo_url: record["logo"],
        contact_address: address_for(record),
        accent_color: accent_for(name),
        source_platform: product.source_platform,
        source_kind: kind.to_s,
        source_id: record["source_id"].to_s.presence,
        source_payload: record.presence || {},
        source_synced_at: Time.current
      }
    end

    #: Fills what the store is missing and overwrites nothing: an operator who
    #: uploaded a logo or banner keeps it, however the source churns.
    def enrich(store, record)
      return false unless store.source_platform.present? && record.present?

      changed = false
      {
        banner_url: record["banner"],
        logo_url: record["logo"],
        contact_address: address_for(record),
        accent_color: store.accent_color.presence || accent_for(store.display_name)
      }.each do |attribute, value|
        next if value.blank? || store.public_send(attribute).present?

        store.public_send("#{attribute}=", value)
        changed = true
      end
      store.save! if changed && !@dry_run
      changed
    end

    def address_for(record)
      parts = [ record["city"], record["state"] ].map { |part| part.to_s.strip }.reject(&:blank?)
      parts.presence&.join(", ")
    end

    #: A stable colour per store, so a storefront with no artwork still has an
    #: identity in the shop instead of rendering grey.
    def accent_for(name)
      palette = %w[#7C3AED #0EA5E9 #F97316 #10B981 #EC4899 #F59E0B #6366F1 #14B8A6]
      palette[Zlib.crc32(name.to_s.downcase) % palette.size]
    end
  end
end
