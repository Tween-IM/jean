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

  private

  def create_item
    @order.commerce_order_items.create!(
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
