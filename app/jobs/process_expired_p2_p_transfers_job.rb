class ProcessExpiredP2PTransfersJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "Starting expired P2P transfer processing job"

    process_expired_transfers
  end

  private

  def process_expired_transfers
    transfers_processed = 0

    begin
      response = WalletService.get_expired_transfers_list

      if response[:transfers].present?
        response[:transfers].each do |transfer|
          if transfer["expired"]
            process_single_expired_transfer(transfer)
            transfers_processed += 1
          end
        end
      end

      Rails.logger.info "Processed #{transfers_processed} expired P2P transfers"
    rescue => e
      Rails.logger.error "Error processing expired P2P transfers: #{e.message}"
      raise
    end
  end

  def process_single_expired_transfer(transfer)
    transfer_id = transfer["transfer_id"]
    Rails.logger.info "Processing expired transfer: #{transfer_id}"

    begin
      result = WalletService.reject_p2p_transfer(transfer_id, "system_expiry")

      if result[:status] == "rejected"
        publish_status_update(transfer)
      end
    rescue => e
      Rails.logger.error "Failed to process expired transfer #{transfer_id}: #{e.message}"
    end
  end

  def publish_status_update(transfer)
    return unless transfer["room_id"]

    MatrixEventService.publish_p2p_status_update(
      transfer["transfer_id"],
      "expired",
      {
        room_id: transfer["room_id"],
        rejected_at: transfer["rejected_at"],
        refund_initiated: true
      }
    )
  end
end
