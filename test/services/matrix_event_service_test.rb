require "test_helper"

class MatrixEventServiceTest < ActiveSupport::TestCase
  setup do
    @user_id = "@alice:tween.example"
    @room_id = "!chat123:tween.example"
    @matrix_api_url = "https://matrix.tween.example"

    MatrixEventService.send(:remove_const, :MATRIX_API_URL) if MatrixEventService.const_defined?(:MATRIX_API_URL)
    MatrixEventService.const_set(:MATRIX_API_URL, @matrix_api_url)
  end

  teardown do
    MatrixEventService.send(:remove_const, :MATRIX_API_URL) if MatrixEventService.const_defined?(:MATRIX_API_URL)
    MatrixEventService.const_set(:MATRIX_API_URL, "https://matrix.example.com")
  end

  test "should have payment_bot method" do
    assert_respond_to MatrixEventService, :payment_bot
  end

  test "should return nil when MATRIX_ACCESS_TOKEN is not set" do
    MatrixEventService.send(:remove_const, :MATRIX_ACCESS_TOKEN) if MatrixEventService.const_defined?(:MATRIX_ACCESS_TOKEN)
    MatrixEventService.const_set(:MATRIX_ACCESS_TOKEN, nil)

    transfer_data = {
      "transfer_id" => "p2p_test123",
      "amount" => 5000.00,
      "currency" => "USD",
      "sender" => { "user_id" => "@alice@tween.example" },
      "recipient" => { "user_id" => "@bob@tween.example" },
      "status" => "completed",
      "room_id" => @room_id
    }

    result = MatrixEventService.publish_p2p_transfer(transfer_data)

    assert_nil result
  end

  test "should publish P2P transfer event" do
    MatrixEventService.send(:remove_const, :MATRIX_ACCESS_TOKEN) if MatrixEventService.const_defined?(:MATRIX_ACCESS_TOKEN)
    MatrixEventService.const_set(:MATRIX_ACCESS_TOKEN, "test_token")

    stub_request(:post, "#{@matrix_api_url}/_matrix/client/v3/rooms/#{CGI.escape(@room_id)}/send/m.room.message")
      .to_return(status: 200, body: '{"event_id":"$test_event_123"}')

    transfer_data = {
      "transfer_id" => "p2p_test123",
      "amount" => 5000.00,
      "currency" => "USD",
      "note" => "Lunch money",
      "sender" => { "user_id" => "@alice@tween.example" },
      "recipient" => { "user_id" => "@bob@tween.example" },
      "status" => "completed",
      "timestamp" => Time.current.iso8601,
      "room_id" => @room_id
    }

    result = MatrixEventService.publish_p2p_transfer(transfer_data)

    assert_not_nil result
  end

  test "should publish gift created event" do
    MatrixEventService.send(:remove_const, :MATRIX_ACCESS_TOKEN) if MatrixEventService.const_defined?(:MATRIX_ACCESS_TOKEN)
    MatrixEventService.const_set(:MATRIX_ACCESS_TOKEN, "test_token")

    stub_request(:post, "#{@matrix_api_url}/_matrix/client/v3/rooms/#{CGI.escape(@room_id)}/send/m.room.message")
      .to_return(status: 200, body: '{"event_id":"$gift_event_123"}')

    gift_data = {
      "gift_id" => "gift_abc123",
      "type" => "split",
      "total_amount" => 10000.00,
      "currency" => "USD",
      "count" => 5,
      "message" => "Happy Birthday!",
      "room_id" => @room_id
    }

    result = MatrixEventService.publish_gift_created(gift_data)

    assert_not_nil result
  end

  test "should publish gift opened event" do
    MatrixEventService.send(:remove_const, :MATRIX_ACCESS_TOKEN) if MatrixEventService.const_defined?(:MATRIX_ACCESS_TOKEN)
    MatrixEventService.const_set(:MATRIX_ACCESS_TOKEN, "test_token")

    stub_request(:post, "#{@matrix_api_url}/_matrix/client/v3/rooms/#{CGI.escape(@room_id)}/send/m.room.message")
      .to_return(status: 200, body: '{"event_id":"$gift_opened_123"}')

    opened_data = {
      "user_id" => "@bob@tween.example",
      "amount" => 2000.00,
      "opened_at" => Time.current.iso8601,
      "remaining_count" => 4,
      "room_id" => @room_id
    }

    result = MatrixEventService.publish_gift_opened("gift_abc123", opened_data)

    assert_not_nil result
  end

  test "should publish authorization event" do
    MatrixEventService.send(:remove_const, :MATRIX_ACCESS_TOKEN) if MatrixEventService.const_defined?(:MATRIX_ACCESS_TOKEN)
    MatrixEventService.const_set(:MATRIX_ACCESS_TOKEN, "test_token")

    stub_request(:post, "#{@matrix_api_url}/_matrix/client/v3/rooms/#{CGI.escape(@room_id)}/send/m.room.message")
      .to_return(status: 200, body: '{"event_id":"$auth_event_123"}')

    result = MatrixEventService.publish_authorization_event(
      "ma_shop_001",
      @user_id,
      true,
      { "room_id" => @room_id }
    )

    assert_not_nil result
  end

  test "should publish miniapp lifecycle event" do
    MatrixEventService.send(:remove_const, :MATRIX_ACCESS_TOKEN) if MatrixEventService.const_defined?(:MATRIX_ACCESS_TOKEN)
    MatrixEventService.const_set(:MATRIX_ACCESS_TOKEN, "test_token")

    stub_request(:post, "#{@matrix_api_url}/_matrix/client/v3/rooms/#{CGI.escape(@room_id)}/send/m.room.message")
      .to_return(status: 200, body: '{"event_id":"$lifecycle_event_123"}')

    app_data = {
      "app_id" => "ma_shop_001",
      "launch_source" => "chat_bubble",
      "launch_params" => { "room_id" => @room_id },
      "session_id" => "session_abc123"
    }

    result = MatrixEventService.publish_miniapp_lifecycle_event("launch", app_data, @user_id, @room_id)

    assert_not_nil result
  end
end
