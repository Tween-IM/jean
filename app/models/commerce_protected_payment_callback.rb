# frozen_string_literal: true

# Idempotency receipt for callbacks delivered by Tween Pay. Consumers must
# tolerate duplicate and out-of-order deliveries; this row is the dedupe key.
class CommerceProtectedPaymentCallback < ApplicationRecord
  before_validation :assign_processed_at

  validates :event_id, :event_type, presence: true
  validates :event_id, uniqueness: true

  def self.record!(event_id:, event_type:, protected_payment_id: nil, payload: {})
    create!(
      event_id: event_id,
      event_type: event_type,
      protected_payment_id: protected_payment_id,
      payload: payload,
      status: "processed",
      processed_at: Time.current
    )
  rescue ActiveRecord::RecordNotUnique
    find_by!(event_id: event_id)
  end

  private

  def assign_processed_at
    self.processed_at ||= Time.current
  end
end
