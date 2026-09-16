# frozen_string_literal: true

module Commerce
  # Fills in branding that the importer already received but never wrote down.
  #
  # A seller store is only as branded as the record the listing carried, and for
  # most of the imported catalogue that record arrived *after* the store was
  # created — a store made from a bare listing never learned the banner or the
  # location its later listings publish. This walks the imported stores and takes
  # what their own listings offer.
  #
  # It only ever fills a blank. An operator who uploaded a banner or a logo keeps
  # it, and a store whose source published nothing keeps nothing: the shop draws
  # a monogram instead of a mark nobody published.
  class StorefrontBrandingBackfill
    #: How many of a store's listings to read before giving up on it. The seller
    #: record is identical across a seller's listings, so the first one that
    #: carries a banner is the answer.
    LISTINGS_PER_STORE = 25

    Summary = Struct.new(:stores_scanned, :stores_filled, :banners, :addresses, :accents, keyword_init: true) do
      def to_s
        "stores scanned: #{stores_scanned} | filled: #{stores_filled} | " \
          "banners: #{banners} | addresses: #{addresses} | accents: #{accents}"
      end
    end

    def initialize(dry_run: true)
      @dry_run = dry_run
      @summary = Summary.new(stores_scanned: 0, stores_filled: 0, banners: 0, addresses: 0, accents: 0)
    end

    def self.call(dry_run: true)
      new(dry_run: dry_run).call
    end

    def call
      imported_stores.find_each do |store|
        @summary.stores_scanned += 1
        record = seller_record_for(store)
        fill(store, record)
      end
      @summary
    end

    private

    def imported_stores
      CommerceStorefront.where.not(source_platform: nil).where.not(source_kind: "brand")
    end

    def seller_record_for(store)
      store.commerce_products
           .where.not(source_payload: nil)
           .limit(LISTINGS_PER_STORE)
           .each do |product|
        payload = product.source_payload
        next unless payload.is_a?(Hash)

        seller = payload["seller"]
        return seller if seller.is_a?(Hash) && branding_present?(seller)
      end
      {}
    end

    def branding_present?(seller)
      seller["banner"].present? || seller["logo"].present? || seller["city"].present? ||
        seller["state"].present? || seller["description"].present?
    end

    def fill(store, record)
      changed = []
      {
        banner_url: record["banner"],
        logo_url: record["logo"],
        about: record["description"],
        contact_address: address_for(record),
        accent_color: store.accent_color.presence || accent_for(store.display_name)
      }.each do |attribute, value|
        next if value.blank? || store.public_send(attribute).present?

        store.public_send("#{attribute}=", value)
        changed << attribute
      end
      return if changed.empty?

      @summary.stores_filled += 1
      @summary.banners += 1 if changed.include?(:banner_url)
      @summary.addresses += 1 if changed.include?(:contact_address)
      @summary.accents += 1 if changed.include?(:accent_color)
      store.save! unless @dry_run
    end

    def address_for(record)
      parts = [ record["city"], record["state"] ].map { |part| part.to_s.strip }.reject(&:blank?)
      parts.presence&.join(", ")
    end

    def accent_for(name)
      palette = %w[#7C3AED #0EA5E9 #F97316 #10B981 #EC4899 #F59E0B #6366F1 #14B8A6]
      palette[Zlib.crc32(name.to_s.downcase) % palette.size]
    end
  end
end
