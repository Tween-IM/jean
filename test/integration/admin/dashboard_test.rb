require "test_helper"

class Admin::DashboardTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(
      matrix_user_id: "@admin:tween.im",
      matrix_username: "admin:tween.im",
      matrix_homeserver: "tween.im",
      platform_role: "super_admin"
    )
  end

  test "dashboard displays stats" do
    post admin_login_path, params: { matrix_user_id: @admin.matrix_user_id }
    get admin_dashboard_path
    assert_response :success
    assert_select "h1", "Dashboard"
  end
end
