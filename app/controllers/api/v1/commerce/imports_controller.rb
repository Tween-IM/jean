# frozen_string_literal: true

# Bulk catalog import/sync for externally-sourced products (Jumia, Konga, ...).
#
# Not reachable by ordinary buyers: the caller must own the target merchant.
# Idempotent by design — the natural source key decides create vs update, so
# the same batch can be replayed safely by a scheduled sync.
class Api::V1::Commerce::ImportsController < Api::V1::Commerce::BaseController
  MAX_ENTRIES = 100

  def create
    require_scope("commerce:merchant")

    merchant = find_import_merchant
    return if ensure_merchant_owner(merchant)

    entries = Array(params[:products])
    if entries.empty?
      return render json: { error: "invalid_request", message: "products[] is required" }, status: :unprocessable_entity
    end
    if entries.size > MAX_ENTRIES
      return render json: {
        error: "invalid_request",
        message: "at most #{MAX_ENTRIES} products per request"
      }, status: :unprocessable_entity
    end

    results = Commerce::ImportService.call(
      merchant: merchant,
      entries: entries,
      storefront_id: params[:storefront_id].presence,
      category_id: params[:category_id].presence,
      storefront: params[:storefront]
    )

    render json: {
      results: results,
      meta: {
        total: results.size,
        created: results.count { |r| r[:action] == "created" },
        updated: results.count { |r| r[:action] == "updated" },
        failed: results.count { |r| r[:action] == "failed" }
      }
    }
  end

  # Cheap reconciliation endpoint: hand it source identities, get back the
  # storefront ids currently linked to them.
  def lookup
    require_scope("commerce:read")

    merchant = find_import_merchant
    return if ensure_merchant_owner(merchant)

    pairs = Array(params[:items]).map do |item|
      attrs = item.respond_to?(:to_unsafe_h) ? item.to_unsafe_h : item.to_h
      [ attrs["source_platform"].to_s, attrs["source_id"].to_s ]
    end.reject { |platform, source_id| platform.blank? || source_id.blank? }

    products = merchant.commerce_products
      .where(source_platform: pairs.map(&:first), source_id: pairs.map(&:last))
      .index_by { |product| [ product.source_platform, product.source_id ] }

    render json: {
      products: pairs.filter_map do |platform, source_id|
        product = products[[ platform, source_id ]]
        next unless product

        {
          source_platform: product.source_platform,
          source_id: product.source_id,
          product_id: product.product_id,
          status: product.status,
          source_synced_at: product.source_synced_at
        }
      end
    }
  end

  private

  # A merchant importing its own products names itself; a marketplace crawl
  # that has no merchant of its own writes to the platform-owned merchant.
  def find_import_merchant
    merchant_id = params[:merchant_id].presence
    return CommerceMerchant.system_merchant if merchant_id.nil?

    CommerceMerchant.find_by!(merchant_id: merchant_id)
  end
end
