require "test_helper"

class UserTest < ActiveSupport::TestCase
  # TMCP Protocol Section 4.1: User model tests

  test "should generate wallet_id on create" do
    user = User.create!(
      matrix_user_id: "@test:tween.example",
      matrix_username: "test:tween.example",
      matrix_homeserver: "tween.example"
    )

    assert_not_nil user.wallet_id
    assert_match /^tw_[a-zA-Z0-9]{12}$/, user.wallet_id
  end

  test "should validate matrix_user_id presence" do
    user = User.new(matrix_username: "test", matrix_homeserver: "tween.example")
    assert_not user.valid?
    assert_includes user.errors[:matrix_user_id], "can't be blank"
  end

  test "should validate matrix_user_id uniqueness" do
    User.create!(
      matrix_user_id: "@test:tween.example",
      matrix_username: "test:tween.example",
      matrix_homeserver: "tween.example"
    )

    duplicate = User.new(
      matrix_user_id: "@test:tween.example",
      matrix_username: "test2:tween.example",
      matrix_homeserver: "tween.example"
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:matrix_user_id], "has already been taken"
  end

  test "should validate matrix_username presence" do
    user = User.new(matrix_user_id: "@test:tween.example", matrix_homeserver: "tween.example")
    assert_not user.valid?
    assert_includes user.errors[:matrix_username], "can't be blank"
  end

  test "should validate matrix_homeserver presence" do
    user = User.new(matrix_user_id: "@test:tween.example", matrix_username: "test:tween.example")
    assert_not user.valid?
    assert_includes user.errors[:matrix_homeserver], "can't be blank"
  end

  test "should have default active status" do
    user = User.create!(
      matrix_user_id: "@test:tween.example",
      matrix_username: "test:tween.example",
      matrix_homeserver: "tween.example"
    )

    assert user.active?
  end

  test "should have associations" do
    user = User.create!(
      matrix_user_id: "@test:tween.example",
      matrix_username: "test:tween.example",
      matrix_homeserver: "tween.example"
    )

    # Test associations exist (even if empty)
    assert_respond_to user, :oauth_applications
    assert_respond_to user, :miniapp_installations
    assert_respond_to user, :installed_miniapps
    assert_respond_to user, :storage_entries
    assert_respond_to user, :mfa_methods
  end
end
