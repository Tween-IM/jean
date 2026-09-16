# frozen_string_literal: true

require "test_helper"

class Admin::CategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    suffix = SecureRandom.hex(4)
    @merchant = CommerceMerchant.system_merchant

    @used = CommerceCategory.create!(name: "Phones #{suffix}", slug: "phones-#{suffix}")
    @used_child = CommerceCategory.create!(name: "Smartphones #{suffix}", slug: "smartphones-#{suffix}", parent_id: @used.id)
    @empty = CommerceCategory.create!(name: "Dead Branch #{suffix}", slug: "dead-#{suffix}")
    @empty_child = CommerceCategory.create!(name: "Dead Leaf #{suffix}", slug: "dead-leaf-#{suffix}", parent_id: @empty.id)
    @parent_with_children = CommerceCategory.create!(name: "Parent Only #{suffix}", slug: "parent-only-#{suffix}")
    CommerceCategory.create!(name: "Live Child #{suffix}", slug: "live-child-#{suffix}", parent_id: @parent_with_children.id)

    @product = @merchant.commerce_products.create!(
      title: "Phone #{suffix}",
      status: "active",
      category_id: @used.id,
      subcategory_id: @used_child.id
    )

    @ops_manager = create_admin("admin-categories-ops-#{suffix}", :operations_manager)
    @support = create_admin("admin-categories-support-#{suffix}", :support)
    @super_admin = create_admin("admin-categories-super-#{suffix}", :super_admin)
  end

  test "anonymous visitors are sent to the admin login" do
    get admin_categories_path
    assert_redirected_to admin_login_path
  end

  test "support can read the tree but not prune it" do
    sign_in_as(@support)

    get admin_categories_path
    assert_response :success
    assert_match "Phones", response.body

    post prune_empty_admin_categories_path
    assert_redirected_to admin_dashboard_path
    assert CommerceCategory.exists?(@empty.id)
  end

  test "the index marks categories that nothing points at" do
    sign_in_as(@super_admin)

    get admin_categories_path

    assert_response :success
    assert_match "Dead Branch", response.body
    assert_match "in use", response.body
    assert_match "nothing filed here", response.body
  end

  test "the empty filter only lists unreferenced categories" do
    sign_in_as(@super_admin)

    get admin_categories_path, params: { filled: "empty" }

    assert_response :success
    # Slugs only appear on rows, so the parent pickers cannot confuse this.
    assert_match ">#{@empty.slug}<", response.body
    refute_match ">#{@used.slug}<", response.body
    refute_match ">#{@used_child.slug}<", response.body
  end

  test "an operator can add a category back" do
    sign_in_as(@ops_manager)

    assert_difference -> { CommerceCategory.count }, 1 do
      post admin_categories_path, params: {
        commerce_category: { name: "Bags", parent_id: @used.id, status: "active" }
      }
    end

    assert_redirected_to admin_categories_path
    created = CommerceCategory.order(:id).last
    assert_equal "Bags", created.name
    assert_equal "bags", created.slug
    assert_equal @used.id, created.parent_id
  end

  test "an operator renames and refiles a category" do
    sign_in_as(@ops_manager)

    patch admin_category_path(@empty), params: {
      commerce_category: { name: "Gadgets", slug: @empty.slug, status: "inactive", sort_order: 5 }
    }

    assert_redirected_to admin_categories_path
    @empty.reload
    assert_equal "Gadgets", @empty.name
    assert_equal "inactive", @empty.status
    assert_equal 5, @empty.sort_order
  end

  # The sweep is bottom-up and repeats: an empty leaf goes first, and a parent
  # that is left with nothing goes on the next pass. Nothing that holds a
  # listing is ever removed.
  test "pruning removes the empty branches and leaves everything in use" do
    sign_in_as(@ops_manager)

    post prune_empty_admin_categories_path

    assert_redirected_to admin_categories_path
    assert_not CommerceCategory.exists?(@empty.id)
    assert_not CommerceCategory.exists?(@empty_child.id)
    assert_not CommerceCategory.exists?(@parent_with_children.id)
    # A branch with listings stays, including the child its listings are filed on.
    assert CommerceCategory.exists?(@used.id)
    assert CommerceCategory.exists?(@used_child.id)
  end

  test "pruning is a no-op when every branch is in use" do
    sign_in_as(@ops_manager)
    Commerce::CategoryPruner.call(dry_run: false)

    post prune_empty_admin_categories_path

    follow_redirect!
    assert_match "No empty categories to remove", response.body
  end

  private

  def sign_in_as(user)
    post admin_login_path, params: {
      matrix_user_id: user.matrix_user_id,
      admin_token: ENV["ADMIN_ACCESS_TOKEN"]
    }
    assert_redirected_to admin_dashboard_path, "expected #{user.platform_role} to sign in"
  end

  def create_admin(username, role)
    user = create_user(username)
    user.update!(platform_role: role)
    user
  end

  def create_user(username)
    User.create!(
      matrix_user_id: "@#{username}:example.com",
      matrix_username: "#{username}:example.com",
      matrix_homeserver: "example.com"
    )
  end
end
