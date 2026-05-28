class RetryWebhookDeliveriesJob < ApplicationJob
  queue_as :default

  def perform(limit: 100)
    WebhookDelivery.due.order(:next_attempt_at, :created_at).limit(limit).find_each(&:deliver_now)
  end
end
