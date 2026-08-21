# frozen_string_literal: true

require "test_helper"

class CommerceRelayServiceTest < ActiveSupport::TestCase
  def setup
    @seller = User.create!(
      matrix_user_id: "@seller:example.com",
      matrix_username: "seller:example.com",
      matrix_homeserver: "example.com"
    )
    @buyer = User.create!(
      matrix_user_id: "@buyer:example.com",
      matrix_username: "buyer:example.com",
      matrix_homeserver: "example.com"
    )
    @merchant = CommerceMerchant.create!(
      owner_user_id: @seller.matrix_user_id,
      miniapp_id: "miniapp.commerce.test",
      display_name: "Inquiry Shop",
      status: "active"
    )
    @product = @merchant.commerce_products.create!(
      title: "Test Product",
      status: "active",
      condition: "new",
      store_type: "marketplace"
    )
    @conversation = CommerceConversation.create!(
      buyer_user_id: @buyer.matrix_user_id,
      product_id: @product.product_id,
      matrix_room_id: "!room:tween.im"
    )
  end

  test "relay_payment_event posts a payment event carrying the note and labels" do
    captured = nil
    CommerceRelayService.define_singleton_method(:make_matrix_request) do |method, path, body|
      captured = [method, path, body]
      { "event_id" => "$relayed" }
    end

    CommerceRelayService.relay_payment_event(
      @conversation,
      transfer_id: "p2p_abc",
      amount: 25.0,
      currency: "NGN",
      status: "completed",
      note: "Thanks for the deal!",
      sender_user_id: @buyer.matrix_user_id,
      sender_label: "buyer label",
      recipient_user_id: @seller.matrix_user_id,
      recipient_label: "Inquiry Shop"
    )

    assert_equal :put, captured[0]
    assert_includes captured[1], "/rooms/%21room%3Atween.im/send/m.tween.wallet.p2p/"
    content = captured[2]
    assert_equal "m.tween.money", content[:msgtype]
    assert_equal "p2p_abc", content[:transfer_id]
    assert_equal 25.0, content[:amount]
    assert_equal "Thanks for the deal!", content[:note]
    assert_equal "buyer label", content[:sender][:display_name]
    assert_equal "Inquiry Shop", content[:recipient][:display_name]
    assert_equal "completed", content[:status]
  end

  test "relay_payment_status posts a status update carrying the transfer id and status" do
    captured = nil
    CommerceRelayService.define_singleton_method(:make_matrix_request) do |method, path, body|
      captured = [method, path, body]
      { "event_id" => "$status1" }
    end

    CommerceRelayService.relay_payment_status(@conversation, "p2p_abc", "completed")

    assert_equal :put, captured[0]
    assert_includes captured[1], "/rooms/%21room%3Atween.im/send/m.tween.wallet.p2p.status/"
    content = captured[2]
    assert_equal "m.tween.money", content[:msgtype]
    assert_equal "p2p_abc", content[:transfer_id]
    assert_equal "completed", content[:status]
    assert_equal "commerce_payment_status", content["m.tween.relay_type"]
  end

  test "relay_payment_status_to_room uses a deterministic Matrix transaction id" do
    paths = []
    CommerceRelayService.define_singleton_method(:make_matrix_request) do |_method, path, _body|
      paths << path
      { "event_id" => "$status" }
    end

    2.times do
      CommerceRelayService.relay_payment_status_to_room(
        "!room:tween.im", "p2p_abc", "completed"
      )
    end

    assert_equal paths.first, paths.last
    assert_equal "$status", CommerceRelayService.relay_payment_status_to_room(
      "!room:tween.im", "p2p_abc", "completed"
    )
  end

  test "relay_payment_event_to_room uses a normal room message and deterministic transaction id" do
    captured = []
    CommerceRelayService.define_singleton_method(:make_matrix_request) do |method, path, body|
      captured << [ method, path, body ]
      { "event_id" => "$payment" }
    end

    payload = {
      transfer_id: "p2p_abc",
      amount: 25,
      currency: "NGN",
      sender: { user_id: "@mona:tween.im", display_name: "Mona" }
    }
    2.times { CommerceRelayService.relay_payment_event_to_room("!room:tween.im", payload) }

    assert_equal :put, captured.first[0]
    assert_includes captured.first[1], "/send/m.room.message/"
    assert_equal captured.first[1], captured.last[1]
    assert_equal "m.tween.money", captured.first[2][:msgtype]
    assert_equal "Mona", captured.first[2][:sender][:display_name]
  end
end
