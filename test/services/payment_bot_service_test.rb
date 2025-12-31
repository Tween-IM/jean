require "test_helper"

class PaymentBotServiceTest < ActiveSupport::TestCase
  setup do
    @payment_bot = PaymentBotService.new(
      as_token: "test_as_token",
      matrix_api_url: "https://core.tween.im"
    )
    @room_id = "!chat123:tween.example"

    # Stub all Matrix API requests
    stub_request(:post, %r{https://core\.tween\.im/_matrix/client/v3/rooms/.*/send/.*})
      .to_return(status: 200, body: '{"event_id":"$test_event_id"}')
  end

  test "#payment_bot_user_id returns correct bot user" do
    assert_equal "@_tmcp_payments:tween.example", @payment_bot.payment_bot_user_id
  end

  test "#send_payment_completed sends rich payment event" do
    payment_data = {
      payment_id: "pay_test123",
      txn_id: "txn_test456",
      amount: 5000.00,
      currency: "USD",
      sender_user_id: "@alice:tween.example",
      sender_display_name: "Alice",
      sender_avatar_url: "mxc://tween.im/avatar1",
      recipient_user_id: "@bob:tween.example",
      recipient_display_name: "Bob",
      recipient_avatar_url: "mxc://tween.im/avatar2",
      note: "Test payment"
    }

    event_id = @payment_bot.send_payment_completed(
      room_id: @room_id,
      payment_data: payment_data
    )

    assert event_id.present?
  end

  test "#send_payment_completed uses idempotency" do
    payment_data = {
      payment_id: "pay_idempotency_test",
      txn_id: "txn_abc123",
      amount: 100.00,
      currency: "USD",
      sender_user_id: "@alice:tween.example",
      sender_display_name: "Alice",
      recipient_user_id: "@bob:tween.example",
      recipient_display_name: "Bob"
    }

    event_id_1 = @payment_bot.send_payment_completed(
      room_id: @room_id,
      payment_data: payment_data
    )

    event_id_2 = @payment_bot.send_payment_completed(
      room_id: @room_id,
      payment_data: payment_data
    )

    assert_equal event_id_1, event_id_2
  end

  test "#send_payment_sent sends sent event" do
    payment_data = {
      payment_id: "pay_sent_test",
      txn_id: "txn_sent456",
      amount: 2500.00,
      currency: "EUR",
      sender_user_id: "@alice:tween.example",
      sender_display_name: "Alice",
      recipient_user_id: "@bob:tween.example",
      recipient_display_name: "Bob"
    }

    event_id = @payment_bot.send_payment_sent(
      room_id: @room_id,
      payment_data: payment_data
    )

    assert event_id.present?
  end

  test "#send_payment_failed sends failed event" do
    payment_data = {
      txn_id: "txn_failed789",
      amount: 100.00,
      currency: "USD",
      sender_user_id: "@alice:tween.example",
      sender_display_name: "Alice",
      recipient_user_id: "@bob:tween.example",
      recipient_display_name: "Bob",
      error_code: "INSUFFICIENT_FUNDS",
      error_message: "Not enough balance"
    }

    event_id = @payment_bot.send_payment_failed(
      room_id: @room_id,
      payment_data: payment_data
    )

    assert event_id.present?
  end

  test "#send_p2p_transfer sends transfer event with idempotency" do
    transfer_data = {
      transfer_id: "p2p_test123",
      amount: 500.00,
      currency: "USD",
      note: "Lunch money",
      sender_user_id: "@alice:tween.example",
      sender_display_name: "Alice",
      recipient_user_id: "@bob:tween.example",
      recipient_display_name: "Bob",
      status: "completed"
    }

    event_id = @payment_bot.send_p2p_transfer(
      room_id: @room_id,
      transfer_data: transfer_data
    )

    assert event_id.present?
  end

  test "should not send event without AS token" do
    no_token_bot = PaymentBotService.new(as_token: nil)

    payment_data = {
      payment_id: "pay_no_token",
      txn_id: "txn_no_token",
      amount: 100.00,
      currency: "USD",
      sender_user_id: "@alice:tween.example",
      sender_display_name: "Alice",
      recipient_user_id: "@bob:tween.example",
      recipient_display_name: "Bob"
    }

    event_id = no_token_bot.send_payment_completed(
      room_id: @room_id,
      payment_data: payment_data
    )

    assert_nil event_id
  end
end
