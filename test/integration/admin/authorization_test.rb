require "test_helper"

class Admin::AuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    @super_admin = User.create!(
      matrix_user_id: "@super:tween.im",
      matrix_username: "super:tween.im",
      matrix_homeserver: "tween.im",
      platform_role: "super_admin"
    )
    @ops_manager = User.create!(
      matrix_user_id: "@ops:tween.im",
      matrix_username: "ops:tween.im",
      matrix_homeserver: "tween.im",
      platform_role: "operations_manager"
    )
    @support = User.create!(
      matrix_user_id: "@support:tween.im",
      matrix_username: "support:tween.im",
      matrix_homeserver: "tween.im",
      platform_role: "support"
    )
  end

  def login_as(user)
    post admin_login_path, params: { matrix_user_id: user.matrix_user_id }
  end

  test "super admin can access dashboard" do
    login_as(@super_admin)
    get admin_dashboard_path
    assert_response :success
  end

  test "operations manager can access dashboard" do
    login_as(@ops_manager)
    get admin_dashboard_path
    assert_response :success
  end

  test "support can access dashboard" do
    login_as(@support)
    get admin_dashboard_path
    assert_response :success
  end

  test "support can view mini apps but not edit" do
    login_as(@support)
    get admin_mini_apps_path
    assert_response :success
  end

  test "support cannot edit mini apps" do
    app = MiniApp.create!(
      app_id: "ma_test001",
      name: "Test App",
      version: "1.0.0",
      classification: :community,
      status: :active,
      client_type: "public",
      manifest: { "permissions" => [], "scopes" => ["storage:read"] }
    )
    login_as(@support)
    get edit_admin_mini_app_path(app)
    assert_redirected_to admin_dashboard_path
  end

  test "operations manager can edit mini apps" do
    app = MiniApp.create!(
      app_id: "ma_test002",
      name: "Test App 2",
      version: "1.0.0",
      classification: :community,
      status: :active,
      client_type: "public",
      manifest: { "permissions" => [], "scopes" => ["storage:read"] }
    )
    login_as(@ops_manager)
    get edit_admin_mini_app_path(app)
    assert_response :success
  end

  test "unauthenticated user is redirected to login" do
    get admin_dashboard_path
    assert_redirected_to admin_login_path
  end

  test "session timeout redirects to login" do
    login_as(@super_admin)
    travel_to 2.hours.from_now do
      get admin_dashboard_path
      assert_redirected_to admin_login_path
      assert_match /expired/, flash[:alert]
    end
  end
end
