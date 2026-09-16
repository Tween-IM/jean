# frozen_string_literal: true

require "test_helper"

# `miniapp_id` names a mini app by its `app_id` (the "ma_..." identifier), and
# the class is `MiniApp`. The association has to spell both out: left to infer,
# Rails looks for a `Miniapp` class and a `miniapp_id` column, and every read
# raises NameError before it can return anything.
class AuthorizationApprovalTest < ActiveSupport::TestCase
  setup do
    @suffix = SecureRandom.hex(4)
    @mini_app = MiniApp.create!(
      app_id: "ma_approvals#{@suffix}",
      name: "Approvals Test App #{@suffix}",
      version: "1.0.0",
      classification: :official,
      status: :active,
      manifest: { "scopes" => [ "user:read" ] }
    )
  end

  test "miniapp resolves through app_id" do
    approval = create_approval(@mini_app.app_id)

    assert_equal @mini_app, approval.miniapp
    assert_equal @mini_app.name, approval.miniapp.name
  end

  test "an approval with no matching mini app reads as nil" do
    approval = create_approval("ma_ghost#{@suffix}")

    assert_nil approval.miniapp
    assert_equal "ma_ghost#{@suffix}", approval.miniapp_id
  end

  private

  def create_approval(miniapp_id)
    AuthorizationApproval.create!(
      user_id: "@approval-#{@suffix}:example.com",
      miniapp_id: miniapp_id,
      scope: "user:read",
      approved_at: Time.current
    )
  end
end
