# frozen_string_literal: true

module Admin
  # Price and stock live on the SKU, not the listing, so catalogue pricing is
  # edited variant by variant. Every change is audited with the before/after.
  class SkusController < BaseController
    before_action -> { require_admin_permission!(:manage_catalog) }
    before_action :set_product
    before_action :set_sku

    def update
      attributes = sku_params.to_h

      if attributes.key?("price")
        price = parse_price(attributes.delete("price"))
        return redirect_to admin_product_path(@product), alert: "Price must be a number." if price.nil?

        attributes["price_cents"] = price
      end

      before = @sku.slice(:price_cents, :quantity_available, :inventory_status, :title)

      if @sku.update(attributes)
        log_admin_action("update_sku", @sku.sku_id, before: before, after: @sku.slice(:price_cents, :quantity_available, :inventory_status, :title))
        redirect_to admin_product_path(@product), notice: "Variant updated."
      else
        redirect_to admin_product_path(@product), alert: "Could not save the variant: #{@sku.errors.full_messages.to_sentence}"
      end
    end

    private

    def set_product
      @product = CommerceProduct.find(params[:product_id])
    end

    def set_sku
      @sku = @product.commerce_skus.find(params[:id])
    end

    # Operators type money, the column stores cents.
    def parse_price(value)
      return nil if value.blank?

      (BigDecimal(value.to_s) * 100).round
    rescue ArgumentError, TypeError
      nil
    end

    def sku_params
      params.require(:commerce_sku).permit(:price, :title, :quantity_available, :inventory_status, :image_url)
    end
  end
end
