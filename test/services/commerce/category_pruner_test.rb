# frozen_string_literal: true

require "test_helper"

# The taxonomy was seeded ahead of the catalogue, so the tree carries branches
# no listing ever landed in. The sweep has to be able to say what it did, and
# it must never take a branch that a listing is filed under — through either
# `category_id` or `subcategory_id`.
class Commerce::CategoryPrunerTest < ActiveSupport::TestCase
  setup do
    suffix = SecureRandom.hex(4)
    @merchant = CommerceMerchant.system_merchant

    @used = CommerceCategory.create!(name: "Phones #{suffix}", slug: "phones-#{suffix}")
    @used_child = CommerceCategory.create!(name: "Smartphones #{suffix}", slug: "smartphones-#{suffix}", parent_id: @used.id)
    @filed_only_by_subcategory = CommerceCategory.create!(name: "Bare Child #{suffix}", slug: "bare-child-#{suffix}")
    @empty = CommerceCategory.create!(name: "Dead Branch #{suffix}", slug: "dead-#{suffix}")
    @empty_child = CommerceCategory.create!(name: "Dead Leaf #{suffix}", slug: "dead-leaf-#{suffix}", parent_id: @empty.id)

    @merchant.commerce_products.create!(title: "Phone #{suffix}", status: "active", category_id: @used.id, subcategory_id: @used_child.id)
    # Filed on the child only: the parent is not named by any product, and the
    # sweep still has to walk up and spare it.
    @merchant.commerce_products.create!(title: "Bare #{suffix}", status: "active", subcategory_id: @filed_only_by_subcategory.id)
  end

  test "a dry run reports what it would remove and changes nothing" do
    before = CommerceCategory.count

    summary = Commerce::CategoryPruner.call(dry_run: true)

    assert_equal before, CommerceCategory.count
    assert_equal @empty.id, CommerceCategory.find_by(id: @empty.id).id
    assert_operator summary.removed, :>, 0
    assert_equal summary.scanned, summary.removed + summary.kept
  end

  test "the sweep takes the whole dead branch and spares everything a listing needs" do
    summary = Commerce::CategoryPruner.call(dry_run: false)

    assert_nil CommerceCategory.find_by(id: @empty.id)
    assert_nil CommerceCategory.find_by(id: @empty_child.id)
    assert CommerceCategory.exists?(@used.id)
    assert CommerceCategory.exists?(@used_child.id)
    assert CommerceCategory.exists?(@filed_only_by_subcategory.id)
    assert_equal summary.scanned, summary.removed + summary.kept
  end

  test "the report is additive and the numbers are the rows that actually went" do
    before = CommerceCategory.count

    summary = Commerce::CategoryPruner.call(dry_run: false)

    assert_equal before, summary.scanned
    assert_equal before - CommerceCategory.count, summary.removed
    assert_equal CommerceCategory.count, summary.kept
  end

  test "a second sweep has nothing left to do" do
    Commerce::CategoryPruner.call(dry_run: false)

    summary = Commerce::CategoryPruner.call(dry_run: false)

    assert_equal 0, summary.removed
  end
end
