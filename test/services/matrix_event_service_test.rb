require "test_helper"

class MatrixEventServiceTest < ActiveSupport::TestCase
  # TMCP Protocol Section 8: Event System tests

  setup do
    @user_id = "@alice:tween.example"
    @room_id = "!chat123:tween.example"
  end

  test "should publish payment completed event" do
    # Section 8.1.2: Payment Events
    payment_data = {
      payment_id: "pay_test123",
      txn_id: "txn_test456",
      amount: 15000.00,
      currency: "USD",
      merchant: {
        miniapp_id: "ma_shop_001",
        name: "Shopping Assistant"
      },
      user_id: @user_id
    }

    event_id = MatrixEventService.publish_payment_completed(payment_data)

    # Event should be "published" (mock implementation)
    assert_not_nil event_id
  end

  test "should publish P2P transfer event" do
    # Section 7.2.2: P2P Transfer Events
    transfer_data = {
      transfer_id: "p2p_test123",
      amount: 5000.00,
      currency: "USD",
      note: "Lunch money",
      sender: { user_id: "@alice:tween.example" },
      recipient: { user_id: "@bob:tween.example" },
      status: "completed",
      timestamp: Time.current.iso8601,
      room_id: @room_id
    }

    event_id = MatrixEventService.publish_p2p_transfer(transfer_data)

    assert_not_nil event_id
  end

  test "should publish P2P status update event" do
    # Section 7.2.2: Status Update Events
    transfer_id = "p2p_status123"
    status = "expired"
    details = {
      expired_at: Time.current.iso8601,
      refunded: true,
      room_id: @room_id
    }

    event_id = MatrixEventService.publish_p2p_status_update(transfer_id, status, details)

    assert_not_nil event_id
  end

  test "should publish gift created event" do
    # Section 7.5.4: Gift Events
    gift_data = {
      gift_id: "gift_test123",
      type: "group",
      total_amount: 10000.00,
      count: 5,
      message: "Happy Friday! 🎁",
      room_id: @room_id
    }

    event_id = MatrixEventService.publish_gift_created(gift_data)

    assert_not_nil event_id
  end

  test "should publish gift opened event" do
    # Section 7.5.4: Gift Opened Events
    gift_id = "gift_opened123"
    opened_data = {
      user_id: "@bob:tween.example",
      amount: 2000.00,
      opened_at: Time.current.iso8601,
      remaining_count: 4,
      room_id: @room_id,
      leaderboard: [
        { user: "@alice:tween.example", amount: 2500.00 },
        { user: "@bob:tween.example", amount: 2000.00 }
      ]
    }

    event_id = MatrixEventService.publish_gift_opened(gift_id, opened_data)

    assert_not_nil event_id
  end

  test "should publish miniapp lifecycle events" do
    # Section 8.1.4: Mini-App Lifecycle Events
    app_data = {
      app_id: "ma_lifecycle_test",
      launch_source: "chat_bubble",
      launch_params: { product_id: "prod_123" },
      session_id: SecureRandom.uuid
    }

    event_id = MatrixEventService.publish_miniapp_lifecycle_event("launch", app_data, @user_id, @room_id)

    assert_not_nil event_id
  end

  test "should publish authorization events" do
    # Section 5.3: Permission Revocation Events
    miniapp_id = "ma_auth_test"
    authorized = false
    details = {
      revoked_at: Time.current.to_i,
      revoked_scopes: [ "wallet:pay" ],
      reason: "user_initiated"
    }

    event_id = MatrixEventService.publish_authorization_event(miniapp_id, @user_id, authorized, details)

    assert_not_nil event_id
  end

  test "should handle event publishing without MATRIX_ACCESS_TOKEN" do
    # Test behavior when Matrix access token is not configured
    original_token = ENV["MATRIX_ACCESS_TOKEN"]
    ENV.delete("MATRIX_ACCESS_TOKEN")

    begin
      payment_data = {
        payment_id: "pay_no_token123",
        txn_id: "txn_no_token456",
        amount: 1000.00,
        currency: "USD",
        merchant: { miniapp_id: "ma_test", name: "Test App" },
        user_id: @user_id
      }

      event_id = MatrixEventService.publish_payment_completed(payment_data)

      # Should return nil when no access token
      assert_nil event_id
    ensure
      ENV["MATRIX_ACCESS_TOKEN"] = original_token
    end
  end

  test "should generate proper event structure for payment completed" do
    payment_data = {
      payment_id: "pay_structure123",
      txn_id: "txn_structure456",
      amount: 25000.00,
      currency: "USD",
      merchant: {
        miniapp_id: "ma_shop_001",
        name: "Test Shop"
      },
      user_id: @user_id
    }

    # Mock the publish_event method to capture the event structure
    event_captured = nil
    MatrixEventService.singleton_class.send(:define_method, :publish_event) do |event|
      event_captured = event
      "mock_event_id"
    end

    begin
      MatrixEventService.publish_payment_completed(payment_data)

      assert_not_nil event_captured
      assert_equal "m.tween.payment.completed", event_captured[:type]
      assert event_captured.key?(:content)
      assert_equal "pay_structure123", event_captured[:content][:payment_id]
      assert_equal "txn_structure456", event_captured[:content][:txn_id]
      assert_equal 25000.00, event_captured[:content][:amount]
      assert_equal "Test Shop", event_captured[:content][:merchant][:name]
    ensure
      # Restore original method
      MatrixEventService.singleton_class.send(:remove_method, :publish_event)
    end
  end

  test "should generate proper event structure for P2P transfer" do
    transfer_data = {
      transfer_id: "p2p_structure123",
      amount: 7500.00,
      currency: "USD",
      note: "Test transfer",
      sender: { user_id: "@alice:tween.example" },
      recipient: { user_id: "@bob:tween.example" },
      status: "completed",
      timestamp: "2025-12-18T14:30:00Z",
      room_id: @room_id
    }

    event_captured = nil
    MatrixEventService.singleton_class.send(:define_method, :publish_event) do |event|
      event_captured = event
      "mock_event_id"
    end

    begin
      MatrixEventService.publish_p2p_transfer(transfer_data)

      assert_not_nil event_captured
      assert_equal "m.tween.wallet.p2p", event_captured[:type]
      assert_equal @room_id, event_captured[:room_id]
      assert_equal "💸 Sent $7500.0", event_captured[:content][:body]
      assert_equal "p2p_structure123", event_captured[:content][:transfer_id]
      assert_equal "completed", event_captured[:content][:status]
    ensure
      MatrixEventService.singleton_class.send(:remove_method, :publish_event)
    end
  end

  test "should include actions in pending P2P transfer events" do
    transfer_data = {
      transfer_id: "p2p_pending123",
      amount: 3000.00,
      currency: "USD",
      note: "Pending transfer",
      sender: { user_id: "@alice:tween.example" },
      recipient: { user_id: "@bob:tween.example" },
      status: "pending_recipient_acceptance",
      timestamp: "2025-12-18T14:30:00Z",
      expires_at: "2025-12-19T14:30:00Z",
      room_id: @room_id
    }

    event_captured = nil
    MatrixEventService.singleton_class.send(:define_method, :publish_event) do |event|
      event_captured = event
      "mock_event_id"
    end

    begin
      MatrixEventService.publish_p2p_transfer(transfer_data)

      assert_not_nil event_captured
      assert event_captured[:content].key?(:actions)
      assert_equal 2, event_captured[:content][:actions].size

      accept_action = event_captured[:content][:actions].find { |a| a[:type] == "accept" }
      reject_action = event_captured[:content][:actions].find { |a| a[:type] == "reject" }

      assert_not_nil accept_action
      assert_not_nil reject_action
      assert accept_action[:endpoint].include?("accept")
      assert reject_action[:endpoint].include?("reject")
    ensure
      MatrixEventService.singleton_class.send(:remove_method, :publish_event)
    end
  end
end
