# frozen_string_literal: true

require "test_helper"

# The sweep pushes listings it has not enriched yet: no brand, no captured
# source store, but a seller name. Those all resolved to "<platform> on Tween",
# so one storefront held hundreds of unrelated sellers — and a product keeps the
# storefront it already has, so re-importing never moved them.
class Commerce::ListingAttributionTest < ActiveSupport::TestCase
  setup do
    @merchant = CommerceMerchant.create!(
      owner_user_id: "@attribution-#{SecureRandom.hex(3)}:example.com",
      miniapp_id: "miniapp.shop.test",
      display_name: "Tween Imports",
      status: "active"
    )
    @catch_all = @merchant.commerce_storefronts.create!(
      display_name: "Konga on Tween", slug: "konga-on-tween", status: "published"
    )
  end

  test "a listing naming a seller moves to that seller's store" do
    product = listing_in_catch_all(
      seller: {
        "name" => "IDA Beauty Shop", "source_id" => "8891",
        "banner" => "https://cdn.tween.im/konga/sellers/8891/banner.jpg",
        "city" => "Ikeja", "state" => "Lagos"
      }
    )

    summary = Commerce::ListingAttribution.call(dry_run: false)

    assert_equal 1, summary.listings_moved
    assert_equal 1, summary.stores_created

    store = product.reload.commerce_storefront
    assert_equal "IDA Beauty Shop", store.display_name
    assert_equal "ida-beauty-shop-konga", store.slug
    assert_equal "ecommerce", store.store_type
    assert_equal "https://cdn.tween.im/konga/sellers/8891/banner.jpg", store.banner_url
    assert_equal "Ikeja, Lagos", store.contact_address
    assert_equal "seller", store.source_kind
    assert_equal "konga", store.source_platform
    assert_match(/\A#[0-9A-F]{6}\z/, store.accent_color)
    refute_equal @catch_all.id, store.id
  end

  test "one store is shared by every listing from the same seller" do
    first = listing_in_catch_all(seller: { "name" => "Oyinkan Stores", "source_id" => "42" })
    second = listing_in_catch_all(seller: { "name" => "Oyinkan Stores", "source_id" => "42" })

    summary = Commerce::ListingAttribution.call(dry_run: false)

    assert_equal 2, summary.listings_moved
    assert_equal 1, summary.stores_created
    assert_equal first.reload.commerce_storefront_id, second.reload.commerce_storefront_id
  end

  test "a listing naming a brand joins the brand store after the seller" do
    product = listing_in_catch_all(
      brand: "Nivea",
      seller: { "name" => "Some Reseller", "source_id" => "7" }
    )

    Commerce::ListingAttribution.call(dry_run: false)

    store = product.reload.commerce_storefront
    assert_equal "Nivea", store.display_name
    assert_equal "nivea", store.slug
    assert_equal "brand", store.source_kind
  end

  test "a listing naming neither is counted and left where it is" do
    product = listing_in_catch_all(seller: {})

    summary = Commerce::ListingAttribution.call(dry_run: false)

    assert_equal 0, summary.listings_moved
    assert_equal 1, summary.without_store
    assert_equal @catch_all.id, product.reload.commerce_storefront_id
  end

  test "the counters on both stores are refreshed by a move" do
    @catch_all.update!(product_count: 500)
    store = @merchant.commerce_storefronts.create!(
      display_name: "Olah", slug: "olah-konga", status: "published", source_platform: "konga"
    )
    listing_in_catch_all(seller: { "name" => "Olah" })

    Commerce::ListingAttribution.call(dry_run: false)

    assert_equal 0, @catch_all.reload.product_count
    assert_equal 1, store.reload.product_count
  end

  test "a dry run reports what it would do without writing" do
    product = listing_in_catch_all(seller: { "name" => "Springhealthwellness" })

    summary = Commerce::ListingAttribution.call(dry_run: true)

    assert_equal 1, summary.listings_moved
    assert_equal 1, summary.stores_created
    assert_equal @catch_all.id, product.reload.commerce_storefront_id
    assert_nil @merchant.commerce_storefronts.find_by(slug: "springhealthwellness-konga")
  end

  test "an existing store keeps branding an operator or an earlier import set" do
    store = @merchant.commerce_storefronts.create!(
      display_name: "Olah", slug: "olah-konga", status: "published",
      banner_url: "https://cdn.tween.im/operator/olah.jpg",
      source_platform: "konga", source_kind: "seller"
    )
    product = listing_in_catch_all(
      seller: { "name" => "Olah", "banner" => "https://cdn/source/olah.jpg" }
    )

    summary = Commerce::ListingAttribution.call(dry_run: false)

    assert_equal 0, summary.stores_created
    assert_equal "https://cdn.tween.im/operator/olah.jpg", store.reload.banner_url
    assert_equal store.id, product.reload.commerce_storefront_id
  end

  test "stores a person created are never touched" do
    personal = @merchant.commerce_storefronts.create!(
      display_name: "Ada's Corner", slug: "adas-corner", status: "published"
    )
    product = @merchant.commerce_products.create!(
      title: "Handmade Bag", status: "active", condition: "new",
      commerce_storefront_id: personal.id
    )

    Commerce::ListingAttribution.call(dry_run: false)

    assert_equal personal.id, product.reload.commerce_storefront_id
  end

  private

  def listing_in_catch_all(seller:, brand: nil)
    payload = { "platform" => "konga", "seller_name" => seller["name"] }.compact
    payload["seller"] = seller if seller.present?
    payload["brand"] = brand if brand.present?

    @merchant.commerce_products.create!(
      title: "Imported Listing #{SecureRandom.hex(3)}",
      status: "active", condition: "new",
      commerce_storefront_id: @catch_all.id,
      source_platform: "konga",
      source_id: SecureRandom.hex(4),
      source_payload: payload
    )
  end
end
