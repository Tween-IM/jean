# frozen_string_literal: true

require "test_helper"

# The admin review queue resolves an appeal to the mini app it is about
# (`appeal.miniapp`), so the association has to find it by `app_id`.
class MiniAppAppealTest < ActiveSupport::TestCase
  setup do
    @suffix = SecureRandom.hex(4)
    @mini_app = MiniApp.create!(
      app_id: "ma_appeals#{@suffix}",
      name: "Appeals Test App #{@suffix}",
      version: "1.0.0",
      classification: :official,
      status: :rejected,
      manifest: { "scopes" => [ "user:read" ] }
    )
  end

  test "an appeal resolves to the mini app it names" do
    appeal = MiniAppAppeal.create!(
      miniapp_id: @mini_app.app_id,
      user_id: "@appeal-#{@suffix}:example.com",
      reason: "It was rejected by mistake",
      status: "pending_review"
    )

    assert_equal @mini_app, appeal.miniapp
  end

  test "the mini app can list its own appeals" do
    appeal = MiniAppAppeal.create!(
      miniapp_id: @mini_app.app_id,
      user_id: "@appeal-#{@suffix}:example.com",
      reason: "Second look please",
      status: "pending_review"
    )

    assert_equal [ appeal.id ], @mini_app.mini_app_appeals.pluck(:id)
  end
end
