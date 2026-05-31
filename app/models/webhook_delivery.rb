# frozen_string_literal: true
class WebhookDelivery < ApplicationRecord
  MAX_ATTEMPTS = 5
  STATUSES = %w[pending delivered failed dead].freeze

  validates :event_id, :event_type, :webhook_url, presence: true
  validates :event_id, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :attempts, numericality: { greater_than_or_equal_to: 0 }

  scope :due, -> { where(status: %w[pending failed]).where("next_attempt_at IS NULL OR next_attempt_at <= ?", Time.current) }

  def deliver_now(service: WebhookService.new)
    service.deliver_record(self)
  end

  def retryable?
    attempts < MAX_ATTEMPTS && status != "delivered"
  end

  def next_retry_at
    [ 2**attempts, 30 ].min.minutes.from_now
  end
end
