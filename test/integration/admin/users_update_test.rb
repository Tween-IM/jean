require "test_helper"

class Admin::UsersUpdateTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(matrix_user_id: "@role_admin_#{SecureRandom.hex(4)}:tween.im",
      matrix_username: "role-admin#{SecureRandom.hex(2)}:tween.im", matrix_homeserver: "tween.im",
      platform_role: "super_admin")
    @person = User.create!(matrix_user_id: "@role_target_#{SecureRandom.hex(4)}:tween.im",
      matrix_username: "role-target#{SecureRandom.hex(2)}:tween.im", matrix_homeserver: "tween.im",
      platform_role: "none")
    post admin_login_path, params: { matrix_user_id: @admin.matrix_user_id, admin_token: ENV["ADMIN_ACCESS_TOKEN"] }
    assert_redirected_to admin_dashboard_path
  end

  test "the edit form's method-overridden submit grants the selected platform role" do
    post admin_user_path(@person),
      params: { _method: "patch", user: { status: "active", platform_role: "support" } }

    assert_redirected_to admin_user_path(@person)
    assert_equal "support", @person.reload.platform_role
    follow_redirect!
    assert_response :success
    assert_select ".admin-flash", text: /User updated successfully/
  end

  test "a failed update surfaces the validation reason" do
    @person.update_column(:matrix_username, "@legacy")

    post admin_user_path(@person),
      params: { _method: "patch", user: { status: "active", platform_role: "support" } }

    assert_response :unprocessable_entity
    assert_select ".admin-flash-alert", text: /Matrix username/
    assert_equal "none", @person.reload.platform_role
  end
end
