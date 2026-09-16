# frozen_string_literal: true

require "test_helper"

# Walking a purchase down its pipeline is what "fulfilling" an order the
# platform sells actually means, so the order has to follow it without an
# operator remembering to update two records.
class Commerce::ProcurementServiceTest < ActiveSupport::TestCase
  setup do
    @suffix = SecureRandom.hex(4)
    @merchant = CommerceMerchant.system_merchant
    @product = @merchant.commerce_products.create!(
      title: "Imported Kettle #{@suffix}",
      status: "active",
      source_platform: "konga",
      source_id: "KETTLE-#{@suffix}",
      supplier_name: "Konga Vendor #{@suffix}",
      supplier_platform: "konga",
      supplier_url: "https://www.konga.com/product/#{@suffix}",
      source_price_cents: 300_00
    )
    @sku = @product.commerce_skus.create!(
      title: "1.7L", price_cents: 450_00, currency: "NGN", quantity_available: 3
    )
    @operator = User.create!(
      matrix_user_id: "@sourcing-op-#{@suffix}:example.com",
      matrix_username: "sourcing-op-#{@suffix}:example.com",
      matrix_homeserver: "example.com"
    )
  end

  test "the whole walk ends with the order fulfilled" do
    order = create_order
    procurement = order.commerce_procurements.first
    assert_equal "pending", procurement.status

    assert_equal "unfulfilled", order.fulfillment_status

    call(procurement, "ordered", cost_cents: 300_00, external_order_ref: "K-8891")
    assert_equal "partially_fulfilled", order.reload.fulfillment_status
    assert_equal "paid", order.status

    call(procurement, "received")
    call(procurement, "dispatched", courier: "GIG", tracking_number: "GIG-77")

    procurement = call(procurement, "delivered")

    assert_equal "delivered", procurement.status
    assert_not_nil procurement.delivered_at
    assert_equal @operator.matrix_user_id, procurement.started_by_user_id
    assert_equal 300_00, procurement.cost_cents
    assert_equal "K-8891", procurement.external_order_ref

    order.reload
    assert_equal "fulfilled", order.fulfillment_status
    assert_equal "fulfilled", order.status
  end

  test "an illegal move is refused and changes nothing" do
    order = create_order
    procurement = order.commerce_procurements.first

    error = assert_raises(Commerce::ProcurementService::Error) do
      call(procurement, "delivered")
    end

    assert_match "cannot move to delivered", error.message
    assert_equal "pending", procurement.reload.status
    assert_nil procurement.delivered_at
  end

  test "a failed purchase can be retried without losing the order" do
    order = create_order
    procurement = order.commerce_procurements.first

    call(procurement, "ordered")
    call(procurement, "failed", notes: "the source had none left")

    assert_equal "failed", procurement.reload.status
    assert_equal "the source had none left", procurement.notes
    assert_includes procurement.next_statuses, "ordered"
    assert_nil procurement.delivered_at

    call(procurement, "ordered", external_order_ref: "K-9002")
    assert_equal "ordered", procurement.reload.status
    assert_equal "K-9002", procurement.external_order_ref
  end

  test "a cancelled line does not hold the rest of the order back" do
    order = create_order(lines: 2)
    first, second = order.commerce_procurements.order(:id).to_a

    call(first, "cancelled", notes: "source sold out, refunded by the desk")

    assert_equal "unfulfilled", order.reload.fulfillment_status

    call(second, "ordered")
    call(second, "received")
    call(second, "dispatched")
    call(second, "delivered")

    order.reload
    assert_equal "fulfilled", order.fulfillment_status
    assert_equal "fulfilled", order.status
  end

  test "one line delivered out of two leaves the order partial" do
    order = create_order(lines: 2)
    first, second = order.commerce_procurements.order(:id).to_a

    call(first, "ordered")
    call(first, "received")
    call(first, "dispatched")
    call(first, "delivered")
    call(second, "ordered")

    assert_equal "partially_fulfilled", order.reload.fulfillment_status
    assert_not_equal "fulfilled", order.status
  end

  test "a merchant's own order is left alone by the pipeline" do
    other = CommerceMerchant.create!(
      owner_user_id: "@own-merchant-#{@suffix}:example.com",
      miniapp_id: "ma.test",
      display_name: "Own Stock #{@suffix}",
      status: "active"
    )
    product = other.commerce_products.create!(title: "Own Kettle #{@suffix}", status: "active")
    order = CommerceOrder.create!(
      commerce_merchant: other,
      buyer_user_id: "@own-buyer-#{@suffix}:example.com",
      payment_id: "pay_own_#{@suffix}",
      status: "paid",
      fulfillment_status: "unfulfilled",
      currency: "NGN",
      total_cents: 100_00
    )
    order.commerce_order_items.create!(
      sku_id: "sku_own_#{@suffix}",
      product_id: product.product_id,
      title: "Own Kettle",
      quantity: 1,
      unit_price_cents: 100_00,
      line_total_cents: 100_00,
      currency: "NGN"
    )

    assert_equal 0, order.commerce_procurements.count
  end

  private

  def call(procurement, status, **attributes)
    Commerce::ProcurementService.call(
      procurement, status: status, attributes: attributes, actor: @operator
    )
  end

  def create_order(lines: 1)
    order = CommerceOrder.create!(
      commerce_merchant: @merchant,
      buyer_user_id: "@sourcing-buyer-#{@suffix}:example.com",
      payment_id: "pay_sourcing_#{@suffix}",
      status: "paid",
      fulfillment_status: "unfulfilled",
      currency: "NGN",
      total_cents: 450_00 * lines
    )

    lines.times do |index|
      order.commerce_order_items.create!(
        sku_id: index.zero? ? @sku.sku_id : "sku_alt_#{index}_#{@suffix}",
        product_id: @product.product_id,
        title: "Imported Kettle",
        quantity: 1,
        unit_price_cents: 450_00,
        line_total_cents: 450_00,
        currency: "NGN"
      )
    end

    order
  end
end
