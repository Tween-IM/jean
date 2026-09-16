# frozen_string_literal: true

module Admin
  # Presentation for the commerce back office: status pills, money in the
  # order's own currency, and the small "is this healthy" signals operators
  # scan for.
  module CommerceHelper
    CURRENCY_SYMBOLS = { "NGN" => "₦", "USD" => "$", "EUR" => "€", "GBP" => "£" }.freeze

    ORDER_STATUS_STYLES = {
      "pending_payment" => "bg-amber-100 text-amber-800",
      "paid" => "bg-blue-100 text-blue-800",
      "processing" => "bg-indigo-100 text-indigo-800",
      "fulfilled" => "bg-emerald-100 text-emerald-800",
      "partially_fulfilled" => "bg-teal-100 text-teal-800",
      "cancelled" => "bg-gray-200 text-gray-700",
      "refunded" => "bg-purple-100 text-purple-800",
      "partially_refunded" => "bg-violet-100 text-violet-800"
    }.freeze

    FULFILLMENT_STATUS_STYLES = {
      "not_required" => "bg-gray-100 text-gray-600",
      "unfulfilled" => "bg-amber-100 text-amber-800",
      "partially_fulfilled" => "bg-teal-100 text-teal-800",
      "fulfilled" => "bg-emerald-100 text-emerald-800",
      "failed" => "bg-red-100 text-red-800"
    }.freeze

    ENTITY_STATUS_STYLES = {
      "active" => "bg-emerald-100 text-emerald-800",
      "published" => "bg-emerald-100 text-emerald-800",
      "draft" => "bg-gray-100 text-gray-700",
      "rejected" => "bg-red-100 text-red-800",
      "archived" => "bg-gray-200 text-gray-700",
      "inactive" => "bg-gray-200 text-gray-700",
      "pending_review" => "bg-amber-100 text-amber-800",
      "suspended" => "bg-red-100 text-red-800",
      "closed" => "bg-gray-300 text-gray-700"
    }.freeze

    PROTECTION_STYLES = {
      "not_eligible" => "bg-gray-100 text-gray-600",
      "eligible" => "bg-blue-100 text-blue-800",
      "active" => "bg-indigo-100 text-indigo-800",
      "completed" => "bg-emerald-100 text-emerald-800",
      "void" => "bg-gray-200 text-gray-700"
    }.freeze

    def money(cents, currency = "NGN")
      return "—" if cents.nil?

      number_to_currency(cents.to_i / 100.0,
        unit: CURRENCY_SYMBOLS.fetch(currency.to_s.upcase, "#{currency} "),
        precision: 2)
    end

    # What a line has to be bought for, and what that leaves.
    #
    # Supplier facts are frozen onto the order line when it is created, so this
    # reads the order rather than the listing: a re-import since the sale must
    # never restate what an order cost.
    def supply_margin(item)
      return nil if item.source_price_cents.nil?

      item.line_total_cents - (item.source_price_cents.to_i * item.quantity.to_i)
    end

    def order_status_badge(status)
      status_pill(status, ORDER_STATUS_STYLES)
    end

    def fulfillment_status_badge(status)
      status_pill(status, FULFILLMENT_STATUS_STYLES)
    end

    def protection_badge(status)
      status_pill(status, PROTECTION_STYLES)
    end

    def entity_status_badge(status)
      status_pill(status, ENTITY_STATUS_STYLES)
    end

    def status_pill(status, palette)
      label = status.to_s.presence || "unknown"
      classes = palette.fetch(label, "bg-slate-100 text-slate-700")

      tag.span(label.humanize, class: "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium #{classes}")
    end

    # A dot + label for "does this need attention", used in tables.
    def signal(label, ok:, detail: nil)
      classes = ok ? "bg-emerald-500" : "bg-amber-500"
      text = ok ? "text-gray-600" : "text-amber-700 font-medium"

      tag.span(class: "inline-flex items-center gap-1.5") do
        tag.span("", class: "w-1.5 h-1.5 rounded-full #{classes}") +
          tag.span(detail.presence || label, class: "text-xs #{text}")
      end
    end

    def store_mark(storefront, size: "w-8 h-8")
      if storefront.logo_url.present?
        tag.img(src: storefront.logo_url, alt: "", class: "#{size} rounded-lg object-cover border border-gray-200")
      else
        initial = storefront.display_name.to_s.first.to_s.upcase
        tag.span(initial,
          class: "#{size} rounded-lg flex items-center justify-center text-xs font-semibold text-white",
          style: "background-color: #{storefront.accent_color.presence || '#4F46E5'}")
      end
    end

    def product_thumb(product, size: "w-10 h-10")
      image = Array(product.media_urls).first
      return tag.span("", class: "#{size} rounded-lg bg-gray-100 border border-gray-200 block") if image.blank?

      tag.img(src: image, alt: "", loading: "lazy", class: "#{size} rounded-lg object-cover border border-gray-200")
    end

    # Reads the loaded association, so a listing table stays one query.
    def pricing_label(product)
      skus = product.commerce_skus.to_a
      prices = skus.map(&:price_cents).compact
      return "—" if prices.empty?

      currency = skus.first&.currency || "NGN"
      shortest = prices.min
      longest = prices.max

      return money(shortest, currency) if shortest == longest

      "#{money(shortest, currency)} – #{money(longest, currency)}"
    end

    def stock_label(product)
      skus = product.commerce_skus.to_a
      return "no variants" if skus.empty?

      total = skus.sum { |sku| sku.quantity_available.to_i }
      out = skus.count { |sku| sku.inventory_status == "out_of_stock" }

      return "#{total} in stock" if out.zero?

      "#{total} in stock · #{out} out"
    end

    def buyer_label(user, fallback)
      return fallback if user.nil?

      user.matrix_username.presence || user.matrix_user_id
    end
  end
end
