# frozen_string_literal: true

require "test_helper"

# Imported marketplace listings arrive with a chain of category *names*
# ("Computers and Accessories" > "Computing Accessories" > "Laptop Chargers").
# Resolving that chain is what makes an imported listing browsable at all —
# the storefront filters products by `category_id`.
class Commerce::CategoryResolverTest < ActiveSupport::TestCase
  test "creates the chain outermost first" do
    hierarchy = Commerce::CategoryResolver.new(
      [ "Test Computers #{SecureRandom.hex(3)}", "Test Laptops" ]
    ).resolve

    assert_equal 2, hierarchy.size
    assert_nil hierarchy.first.parent_id
    assert_equal hierarchy.first.id, hierarchy.last.parent_id
  end

  test "namespaces a child slug under its parent" do
    suffix = SecureRandom.hex(3)
    resolver = Commerce::CategoryResolver.new([ "Test Computing #{suffix}", "Test Accessories" ])

    hierarchy = resolver.resolve

    assert_equal "test-computing-#{suffix}", hierarchy.first.slug
    assert hierarchy.last.slug.start_with?("test-computing-#{suffix}-")
  end

  test "reuses a branch that already exists by name" do
    name = "Test Phones #{SecureRandom.hex(3)}"
    existing = CommerceCategory.create!(name: name, slug: name.parameterize, status: "active")

    hierarchy = Commerce::CategoryResolver.new([ name ]).resolve

    assert_equal existing.id, hierarchy.first.id
    assert_equal 1, CommerceCategory.where("lower(name) = ?", name.downcase).count
  end

  test "re-running a chain does not duplicate it" do
    path = [ "Test Home #{SecureRandom.hex(3)}", "Test Kitchen #{SecureRandom.hex(3)}" ]

    first = Commerce::CategoryResolver.new(path).resolve
    second = Commerce::CategoryResolver.new(path).resolve

    assert_equal first.map(&:id), second.map(&:id)
    assert_equal 2, CommerceCategory.where(id: first.map(&:id)).count
  end

  test "a deeper second pass extends the same chain" do
    path = [ "Test Electronics #{SecureRandom.hex(3)}" ]
    root = Commerce::CategoryResolver.new(path).resolve.first

    hierarchy = Commerce::CategoryResolver.new(path + [ "Test Televisions" ]).resolve

    assert_equal root.id, hierarchy.first.id
    assert_equal root.id, hierarchy.last.parent_id
  end

  test "the chain is capped so marketplace noise is not a taxonomy" do
    suffix = SecureRandom.hex(3)
    path = (1..9).map { |depth| "Test Level #{depth} #{suffix}" }

    hierarchy = Commerce::CategoryResolver.new(path).resolve

    assert_equal Commerce::CategoryResolver::MAX_DEPTH, hierarchy.size
  end

  test "blank and duplicate names are dropped" do
    suffix = SecureRandom.hex(3)
    hierarchy = Commerce::CategoryResolver.new(
      [ "", "  ", "Test Only #{suffix}", "Test Only #{suffix}" ]
    ).resolve

    assert_equal 1, hierarchy.size
    assert_equal "test only #{suffix}", hierarchy.first.name.downcase
  end

  test "an empty path resolves to nothing rather than an error" do
    assert_equal [], Commerce::CategoryResolver.new([]).resolve
    assert_equal [], Commerce::CategoryResolver.new(nil).resolve
  end

  test "a category is created active so it is browsable immediately" do
    hierarchy = Commerce::CategoryResolver.new([ "Test Live #{SecureRandom.hex(3)}" ]).resolve

    assert_equal "active", hierarchy.first.status
  end
end
