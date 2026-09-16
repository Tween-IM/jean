# frozen_string_literal: true

require "test_helper"

# An order line records where its goods were to be bought from. The listing's
# supplier is rewritten by every import, so an order that only pointed at the
# listing would silently restate history.
class CommerceOrderItemTest < ActiveSupport::TestCase
  setup do
    @suffix = SecureRandom.hex(4)
    @merchant = CommerceMerchant.system_merchant
    @product = @merchant.commerce_products.create!(
      title: "Ankara Print Dress #{@suffix}",
      status: "active",
      source_platform: "konga",
      source_id: "SKU-#{@suffix}",
      supplier_name: "Chimaco Stores",
      supplier_id: "8811",
      supplier_platform: "konga",
      supplier_url: "https://www.konga.com/product/#{@suffix}",
      source_price_cents: 250_00,
      brand: "Bella Couture"
    )
    @order = CommerceOrder.create!(
      commerce_merchant: @merchant,
      buyer_user_id: "@order-item-buyer-#{@suffix}:example.com",
      payment_id: "pay_order_item_#{@suffix}",
      status: "paid",
      currency: "NGN",
      total_cents: 400_00
    )
  end

  test "a line freezes the supplier it was bought from" do
    item = create_item

    assert_equal "Chimaco Stores", item.supplier_name
    assert_equal "8811", item.supplier_id
    assert_equal "konga", item.supplier_platform
    assert_equal 250_00, item.source_price_cents
    assert_equal "Bella Couture", item.brand
  end

  test "a later import does not rewrite what an order already recorded" do
    item = create_item

    @product.update!(supplier_name: "Someone Else", source_price_cents: 900_00)

    assert_equal "Chimaco Stores", item.reload.supplier_name
    assert_equal 250_00, item.source_price_cents
  end

  test "a line naming no listing keeps the fields it was given" do
    item = @order.commerce_order_items.create!(
      sku_id: "sku_#{@suffix}",
      product_id: "prod_missing_#{@suffix}",
      title: "Hand-delivered service",
      quantity: 1,
      unit_price_cents: 5_000,
      line_total_cents: 5_000,
      currency: "NGN"
    )

    assert_nil item.supplier_name
    assert_equal "Hand-delivered service", item.title
  end

  # ── The platform buys nothing until somebody buys it ─────────────────

  test "nothing is queued to be bought before the order is paid" do
    order = build_order(status: "pending_payment")
    item = create_item(order: order)

    assert_nil item.reload.commerce_procurement
  end

  test "paying for the order queues its lines to be bought" do
    order = build_order(status: "pending_payment")
    item = create_item(order: order)

    order.update!(status: "paid")

    procurement = item.reload.commerce_procurement
    assert_not_nil procurement
    assert_equal "pending", procurement.status
    assert_equal "Chimaco Stores", procurement.supplier_name
    assert_equal "https://www.konga.com/product/#{@suffix}", procurement.supplier_url
    assert_equal "NGN", procurement.currency
    assert_equal order.order_id, procurement.commerce_order.order_id
  end

  test "a merchant's own order is never sourced by the platform" do
    merchant = CommerceMerchant.create!(
      owner_user_id: "@own-stock-seller-#{@suffix}:example.com",
      miniapp_id: "ma.test",
      display_name: "Own Stock Shop #{@suffix}",
      status: "active"
    )
    product = merchant.commerce_products.create!(title: "Shop Cap #{@suffix}", status: "active")
    order = CommerceOrder.create!(
      commerce_merchant: merchant,
      buyer_user_id: "@own-stock-buyer-#{@suffix}:example.com",
      payment_id: "pay_own_stock_#{@suffix}",
      status: "paid",
      currency: "NGN",
      total_cents: 1_000
    )

    item = order.commerce_order_items.create!(
      sku_id: "sku_own_#{@suffix}",
      product_id: product.product_id,
      title: "Shop Cap",
      quantity: 1,
      unit_price_cents: 1_000,
      line_total_cents: 1_000,
      currency: "NGN"
    )
    order.update!(status: "processing")

    assert_nil item.reload.commerce_procurement
  end

  test "a cancelled order takes its unstarted purchase out of the queue" do
    order = build_order(status: "pending_payment")
    item = create_item(order: order)
    order.update!(status: "paid")
    procurement = item.reload.commerce_procurement
    assert_not_nil procurement

    order.update!(status: "cancelled")

    assert_equal "cancelled", procurement.reload.status
    assert_match "Cancelled automatically", procurement.notes
    assert_equal 0, CommerceProcurement.open.count
  end

  private

  def build_order(status:)
    CommerceOrder.create!(
      commerce_merchant: @merchant,
      buyer_user_id: "@order-item-buyer-#{@suffix}:example.com",
      payment_id: "pay_order_item_#{status}_#{@suffix}",
      status: status,
      currency: "NGN",
      total_cents: 400_00
    )
  end

  def create_item(order: @order)
    order.commerce_order_items.create!(
      sku_id: @product.commerce_skus.create!(
        title: "Medium", price_cents: 400_00, currency: "NGN", quantity_available: 3
      ).sku_id,
      product_id: @product.product_id,
      title: @product.title,
      quantity: 2,
      unit_price_cents: 400_00,
      line_total_cents: 800_00,
      currency: "NGN"
    )
  end
end
