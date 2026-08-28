# frozen_string_literal: true

# A versioned structured offer negotiated inside a commerce conversation.
#
# Proposed offers are immutable. Editing or counteroffering creates a new
# version that supersedes the previous one. Acceptance copies the accepted
# terms into an immutable order snapshot.
class CommerceOffer < ApplicationRecord
  OFFER_TYPES = %w[product service].freeze
  STATUSES = %w[draft proposed accepted declined expired superseded].freeze

  belongs_to :commerce_conversation, foreign_key: :conversation_id,
                                     primary_key: :conversation_id,
                                     inverse_of: :commerce_offers

  before_validation :assign_offer_id
  before_validation :set_defaults

  validates :offer_id, :conversation_id, :proposer_user_id, :recipient_user_id, presence: true
  validates :offer_id, uniqueness: true
  validates :offer_type, inclusion: { in: OFFER_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :version, numericality: { only_integer: true, greater_than: 0 }
  validates :total_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :for_conversation, ->(conversation_id) { where(conversation_id: conversation_id) }

  def accepted?
    status == "accepted"
  end

  def expired?
    status == "expired" || (expires_at.present? && Time.current > expires_at)
  end

  def superseded?
    status == "superseded" || superseded_by_offer_id.present?
  end

  def offer_json(detail: :public)
    {
      offer_id: offer_id,
      conversation_id: conversation_id,
      proposer_user_id: proposer_user_id,
      recipient_user_id: recipient_user_id,
      offer_type: offer_type,
      version: version,
      status: status,
      currency: currency,
      subtotal_cents: subtotal_cents,
      delivery_fee_cents: delivery_fee_cents,
      buyer_fee_cents: buyer_fee_cents,
      discount_cents: discount_cents,
      total_cents: total_cents,
      commission_cents: commission_cents,
      seller_proceeds_cents: seller_proceeds_cents,
      expires_at: expires_at,
      terms: terms_json,
      superseded_by_offer_id: superseded_by_offer_id,
      accepted_at: accepted_at,
      accepted_by_user_id: accepted_by_user_id,
      order_id: order_id,
      created_at: created_at
    }.tap do |base|
      base.merge!(responded_at: responded_at) if responded_at.present?
    end
  end

  private

  def assign_offer_id
    return if offer_id.present?

    self.offer_id = "off_#{SecureRandom.alphanumeric(12).downcase}"
  end

  def set_defaults
    self.version ||= 1
    self.status ||= "draft"
    self.currency ||= "NGN"
    self.terms_json ||= {}
  end
end
