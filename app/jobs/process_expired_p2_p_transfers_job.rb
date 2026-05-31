# frozen_string_literal: true

class ProcessExpiredP2PTransfersJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "Starting expired P2P transfer processing job"

    transfers = PendingTransfer.where(status: %w[initiated pending_recipient_acceptance])
                               .where("expires_at < ?", Time.current)

    transfers_processed = 0

    transfers.find_each do |transfer|
      process_single_expired_transfer(transfer)
      transfers_processed += 1
    end

    Rails.logger.info "Processed #{transfers_processed} expired P2P transfers"
  end

  private

  def process_single_expired_transfer(transfer)
    Rails.logger.info "Processing expired transfer: #{transfer.id}"

    transfer.update!(
      status: "expired",
      metadata: (transfer.metadata || {}).merge(
        "expired_at" => Time.current.iso8601,
        "expired_by" => "system_expiry"
      )
    )

    publish_status_update(transfer)
  rescue StandardError => e
    Rails.logger.error "Failed to process expired transfer #{transfer.id}: #{e.message}"
  end

  def publish_status_update(transfer)
    return unless transfer.room_id

    MatrixEventService.publish_p2p_status_update(
      "p2p_#{transfer.id}",
      "expired",
      {
        room_id: transfer.room_id,
        rejected_at: Time.current.iso8601,
        refund_initiated: true
      }
    )
  rescue StandardError => e
    Rails.logger.error "Failed to publish expiry event for transfer #{transfer.id}: #{e.message}"
  end
end
