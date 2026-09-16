# frozen_string_literal: true

require "test_helper"

# A seller store is only as branded as the record its listings carried, and for
# most of the imported catalogue that record arrived after the store was made.
class Commerce::StorefrontBrandingBackfillTest < ActiveSupport::TestCase
  setup do
    @merchant = CommerceMerchant.create!(
      owner_user_id: "@branding-#{SecureRandom.hex(3)}:example.com",
      miniapp_id: "miniapp.shop.test",
      display_name: "Tween Imports",
      status: "active"
    )
  end

  test "a store takes the banner and location its own listing publishes" do
    store = imported_store("Undies island", "undies-island-konga")
    listing(store, seller: {
      "name" => "Undies island",
      "banner" => "https://cdn.tween.im/konga/sellers/1/banner.jpg",
      "city" => "Ikeja", "state" => "Lagos"
    })

    summary = Commerce::StorefrontBrandingBackfill.call(dry_run: false)

    assert_equal 1, summary.stores_filled
    assert_equal 1, summary.banners
    assert_equal "https://cdn.tween.im/konga/sellers/1/banner.jpg", store.reload.banner_url
    assert_equal "Ikeja, Lagos", store.contact_address
    assert_match(/\A#[0-9A-F]{6}\z/, store.accent_color)
  end

  test "branding an operator set is never overwritten" do
    store = imported_store("Olah", "olah-konga")
    store.update!(banner_url: "https://cdn.tween.im/operator/olah.jpg")
    listing(store, seller: { "name" => "Olah", "banner" => "https://cdn/source/olah.jpg" })

    Commerce::StorefrontBrandingBackfill.call(dry_run: false)

    assert_equal "https://cdn.tween.im/operator/olah.jpg", store.reload.banner_url
  end

  test "a store whose listings publish nothing is left bare" do
    store = imported_store("Citadel Store", "citadel-store-konga")
    listing(store, seller: { "name" => "Citadel Store" })

    summary = Commerce::StorefrontBrandingBackfill.call(dry_run: false)

    assert_equal 0, summary.stores_filled
    assert_nil store.reload.banner_url
    assert_nil store.logo_url, "no logo is ever invented for a seller"
  end

  test "brand stores and stores a person created are not touched" do
    brand = @merchant.commerce_storefronts.create!(
      display_name: "Samsung", slug: "samsung", status: "published",
      source_platform: "konga", source_kind: "brand"
    )
    manual = @merchant.commerce_storefronts.create!(
      display_name: "Ada's Corner", slug: "adas-corner", status: "published"
    )
    listing(brand, seller: { "name" => "Some Reseller", "banner" => "https://cdn/b.jpg" })
    listing(manual, seller: { "name" => "Ada", "banner" => "https://cdn/a.jpg" })

    summary = Commerce::StorefrontBrandingBackfill.call(dry_run: false)

    assert_equal 0, summary.stores_scanned
    assert_nil brand.reload.banner_url
    assert_nil manual.reload.banner_url
  end

  test "a dry run reports without writing" do
    store = imported_store("BlossomStores", "blossomstores-konga")
    listing(store, seller: { "name" => "BlossomStores", "banner" => "https://cdn/b.jpg" })

    summary = Commerce::StorefrontBrandingBackfill.call(dry_run: true)

    assert_equal 1, summary.stores_filled
    assert_nil store.reload.banner_url
  end

  private

  def imported_store(name, slug)
    @merchant.commerce_storefronts.create!(
      display_name: name, slug: slug, status: "published",
      source_platform: "konga", source_kind: "seller"
    )
  end

  def listing(store, seller:)
    @merchant.commerce_products.create!(
      title: "Imported #{SecureRandom.hex(3)}", status: "active", condition: "new",
      commerce_storefront_id: store.id, source_platform: "konga",
      source_id: SecureRandom.hex(4),
      source_payload: { "platform" => "konga", "seller_name" => seller["name"], "seller" => seller }
    )
  end
end
