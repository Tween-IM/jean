require "test_helper"

class WebhookServiceTest < ActiveSupport::TestCase
  test "deliver records webhook delivery in test environment" do
    assert_difference "WebhookDelivery.count", 1 do
      assert WebhookService.new.deliver(event_type: "commerce.order.updated", payload: { order_id: "ord_test" }, webhook_url: "https://merchant.example/webhooks", event_id: "evt_test")
    end

    delivery = WebhookDelivery.find_by!(event_id: "evt_test")
    assert_equal "pending", delivery.status
    assert_equal "commerce.order.updated", delivery.event_type
    assert_equal({ "order_id" => "ord_test" }, delivery.payload)
  end
end
