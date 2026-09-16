# frozen_string_literal: true

require "test_helper"

# A mirrored listing names two different parties: the brand it belongs to and
# the seller that fulfils it. Both arrived inside `source_payload`, which made
# neither queryable — no browsing by brand, and no way for an order to say
# where its goods come from.
class CommerceProductTest < ActiveSupport::TestCase
  setup do
    @suffix = SecureRandom.hex(4)
    @merchant = CommerceMerchant.system_merchant
    @product = @merchant.commerce_products.create!(
      title: "Ankara Print Dress #{@suffix}",
      status: "active",
      source_platform: "konga",
      source_id: "SKU-#{@suffix}",
      source_url: "https://www.konga.com/product/#{@suffix}"
    )
  end

  test "the brand and the supplier are read out of the payload" do
    @product.update!(source_payload: {
      "brand" => "Samsung",
      "seller_name" => "Chimaco Stores",
      "seller_id" => "8811",
      "price_cents" => 420_00
    })

    identity = @product.source_identity

    assert_equal "Samsung", identity[:brand]
    assert_equal "Chimaco Stores", identity[:supplier_name]
    assert_equal "8811", identity[:supplier_id]
    assert_equal "konga", identity[:supplier_platform]
    assert_equal "https://www.konga.com/product/#{@suffix}", identity[:supplier_url]
    assert_equal 420_00, identity[:source_price_cents]
  end

  test "the seller record wins over the flattened seller fields" do
    @product.update!(source_payload: {
      "brand" => "Nokia",
      "seller_name" => "Stale Name",
      "seller_id" => "1",
      "seller" => { "name" => "Kriscrown global links", "id" => "99" }
    })

    identity = @product.source_identity

    assert_equal "Kriscrown global links", identity[:supplier_name]
    assert_equal "99", identity[:supplier_id]
  end

  test "a listing the source published nothing about reads as blank, not as a guess" do
    @product.update!(source_payload: { "platform" => "konga" })

    identity = @product.source_identity

    assert_nil identity[:brand]
    assert_nil identity[:supplier_name]
    assert_nil identity[:source_price_cents]
  end

  test "applying the identity writes the columns" do
    @product.update!(source_payload: { "brand" => "Nokia", "seller_name" => "Chimaco Stores", "price_cents" => 12_500 })

    @product.apply_source_identity!
    @product.reload

    assert_equal "Nokia", @product.brand
    assert_equal "Chimaco Stores", @product.supplier_name
    assert_equal 12_500, @product.source_price_cents
  end

  test "a later import that names no seller does not erase the one we knew" do
    @product.update!(source_payload: { "brand" => "Nokia", "seller_name" => "Chimaco Stores" })
    @product.apply_source_identity!

    # The sweep re-imports a listing it has not enriched: brand only.
    @product.update!(source_payload: { "brand" => "Nokia" })
    @product.apply_source_identity!
    @product.reload

    assert_equal "Nokia", @product.brand
    assert_equal "Chimaco Stores", @product.supplier_name
  end
end
