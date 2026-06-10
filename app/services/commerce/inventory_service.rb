# frozen_string_literal: true

module Commerce
  class InventoryService
    def self.reserve!(cart)
      new.reserve!(cart)
    end

    def self.restore!(order)
      new.restore!(order)
    end

    # Lock SKUs in consistent ID order and decrement available quantity.
    def reserve!(cart)
      sku_ids = cart.commerce_cart_items.pluck(:commerce_sku_id).sort
      locked_skus = ::CommerceSku.where(id: sku_ids).lock.to_a.index_by(&:id)

      cart.commerce_cart_items.includes(:commerce_sku).each do |item|
        sku = locked_skus[item.commerce_sku_id]
        next if sku.nil? || sku.quantity_available.nil?
        raise ActiveRecord::RecordInvalid, item unless sku.available?(item.quantity)

        sku.update!(quantity_available: sku.quantity_available - item.quantity)
      end
    end

    # Return reserved stock to the pool. Idempotent via metadata guard.
    def restore!(order)
      return if order.metadata["inventory_restored"]

      order.commerce_order_items.each do |item|
        sku = ::CommerceSku.lock.find_by(sku_id: item.sku_id)
        next unless sku&.quantity_available

        sku.update!(quantity_available: sku.quantity_available + item.quantity)
      end
    end
  end
end
