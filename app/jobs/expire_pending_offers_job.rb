# frozen_string_literal: true

# Marks proposed offers as expired once their expiry time passes. Idempotent:
# accepted/superseded offers are never touched.
class ExpirePendingOffersJob < ApplicationJob
  queue_as :default

  def perform
    CommerceOffer.where(status: "proposed")
                 .where("expires_at IS NOT NULL AND expires_at <= ?", Time.current)
                 .find_each do |offer|
      offer.update!(status: "expired", responded_at: offer.responded_at || Time.current)
    end
  end
end
