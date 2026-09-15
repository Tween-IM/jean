# frozen_string_literal: true

module Admin
  # Presentation helpers for the imported-catalog screens.
  module ImportsHelper
    CURRENCY_SYMBOLS = { "NGN" => "₦", "USD" => "$", "EUR" => "€", "GBP" => "£" }.freeze

    # Colour-coded badge for a source platform (jumia, konga, ...).
    def platform_badge(platform)
      palette = {
        "jumia" => "bg-orange-100 text-orange-800",
        "konga" => "bg-purple-100 text-purple-800"
      }
      classes = palette.fetch(platform.to_s.downcase, "bg-slate-100 text-slate-700")
      tag.span(platform.presence || "unknown",
        class: "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium #{classes}")
    end

    # `seller` / `brand` badge for an imported store.
    def source_kind_badge(kind)
      classes = kind == "brand" ? "bg-blue-100 text-blue-800" : "bg-emerald-100 text-emerald-800"
      tag.span(kind.presence || "store",
        class: "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium #{classes}")
    end

    # Green when we have a way to reach the seller, amber when we do not.
    def contact_badge(storefront)
      if [ storefront.contact_phone, storefront.contact_email, storefront.contact_website,
           storefront.contact_address ].any?(&:present?)
        tag.span("contact on file",
          class: "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-emerald-100 text-emerald-800")
      else
        tag.span("no contact",
          class: "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-amber-100 text-amber-800")
      end
    end

    # Lowest SKU price, or a range when the SKUs disagree.
    def import_price(product)
      range = product.price_range
      return "—" if range.nil?

      formatted = ->(cents) do
        number_to_currency(cents / 100.0,
          unit: CURRENCY_SYMBOLS.fetch(range[:currency].to_s.upcase, ""),
          precision: 2)
      end
      return formatted.call(range[:min]) if range[:min] == range[:max]

      "#{formatted.call(range[:min])} – #{formatted.call(range[:max])}"
    end

    # A single variant's price, in the currency the source quoted it in.
    def sku_price(sku)
      currency = sku.currency.to_s.upcase
      number_to_currency(sku.price_cents / 100.0,
        unit: CURRENCY_SYMBOLS.fetch(currency, currency),
        precision: 2)
    end

    def sync_label(time)
      time.present? ? "#{time_ago_in_words(time)} ago" : "never synced"
    end

    # States an operator may set from the imported-catalog screens. Kept next
    # to the controller constants they mirror so the two cannot drift.
    def product_status_options
      Admin::ImportsController::PRODUCT_STATUSES
    end

    def review_status_options
      Admin::ImportsController::REVIEW_STATUSES
    end
  end
end
