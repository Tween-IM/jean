require "test_helper"

class Admin::SessionsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(
      matrix_user_id: "@admin:tween.im",
      matrix_username: "admin:tween.im",
      matrix_homeserver: "tween.im",
      platform_role: "super_admin"
    )
    @regular_user = User.create!(
      matrix_user_id: "@user:tween.im",
      matrix_username: "user:tween.im",
      matrix_homeserver: "tween.im",
      platform_role: "none"
    )
  end

  test "login page is accessible" do
    get admin_login_path
    assert_response :success
    assert_select "h1", "TMCP Admin"
  end

  test "admin can log in with matrix user id" do
    post admin_login_path, params: { matrix_user_id: @admin.matrix_user_id }
    assert_redirected_to admin_dashboard_path
    assert_equal @admin.id, session[:admin_user_id]
  end

  test "non-admin cannot log in" do
    post admin_login_path, params: { matrix_user_id: @regular_user.matrix_user_id }
    assert_response :unprocessable_entity
    assert_nil session[:admin_user_id]
  end

  test "invalid user cannot log in" do
    post admin_login_path, params: { matrix_user_id: "@nonexistent:tween.im" }
    assert_response :unprocessable_entity
    assert_nil session[:admin_user_id]
  end

  test "admin can log out" do
    post admin_login_path, params: { matrix_user_id: @admin.matrix_user_id }
    delete admin_logout_path
    assert_redirected_to admin_login_path
    assert_nil session[:admin_user_id]
  end

  test "logged in admin is redirected from login page" do
    post admin_login_path, params: { matrix_user_id: @admin.matrix_user_id }
    get admin_login_path
    assert_redirected_to admin_dashboard_path
  end

  test "admin with mfa is prompted for code" do
    @admin.update!(admin_mfa_enabled: true, admin_mfa_secret: ROTP::Base32.random)
    post admin_login_path, params: { matrix_user_id: @admin.matrix_user_id }
    assert_response :success
    assert_select "h1", "Two-Factor Authentication"
    assert_equal @admin.id, session[:admin_mfa_pending_user_id]
  end

  test "admin with mfa can verify and log in" do
    secret = ROTP::Base32.random
    @admin.update!(admin_mfa_enabled: true, admin_mfa_secret: secret)
    code = ROTP::TOTP.new(secret).now

    post admin_login_path, params: { matrix_user_id: @admin.matrix_user_id }
    post admin_mfa_path, params: { mfa_code: code }
    assert_redirected_to admin_dashboard_path
    assert_equal @admin.id, session[:admin_user_id]
  end

  test "invalid mfa code is rejected" do
    secret = ROTP::Base32.random
    @admin.update!(admin_mfa_enabled: true, admin_mfa_secret: secret)

    post admin_login_path, params: { matrix_user_id: @admin.matrix_user_id }
    post admin_mfa_path, params: { mfa_code: "000000" }
    assert_response :unprocessable_entity
    assert_nil session[:admin_user_id]
  end
end
