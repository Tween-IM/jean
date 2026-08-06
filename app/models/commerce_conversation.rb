# frozen_string_literal: true

# A classified (marketplace) buyer↔seller conversation.
#
# Privacy: buyer and seller are NEVER members of the same Matrix room and
# never see each other's Tween/Matrix IDs. The relay bot owns a single room
# and relays messages with friendly labels (see CommerceRelayService).
#
# Dedup: one conversation per (buyer_user_id, product_id).
class CommerceConversation < ApplicationRecord
  before_validation :assign_conversation_id

  validates :conversation_id, :buyer_user_id, :product_id, presence: true
  validates :conversation_id, uniqueness: true
  validates :status, inclusion: { in: %w[open closed dm_pending dm_active] }

  def product
    @product ||= ::CommerceProduct.find_by(product_id: product_id)
  end

  def merchant
    product&.commerce_merchant
  end

  def seller_user_id
    merchant&.owner_user_id
  end

  def buyer_label
    # Never expose the raw buyer Matrix ID. Fall back to a generic label.
    profile = ::SocialCreatorProfile.find_by(user_id: buyer_user_id)
    profile&.display_name.presence || profile&.handle.presence || "Buyer"
  end

  def seller_label
    merchant&.display_name.presence || "Seller"
  end

  def last_read_at_for(role)
    role == "seller" ? seller_last_read_at : buyer_last_read_at
  end

  def unread_for?(role)
    return false unless last_message_at.present?

    last_read = last_read_at_for(role)
    last_read.nil? || last_message_at > last_read
  end

  def mark_read!(role)
    column = role == "seller" ? :seller_last_read_at : :buyer_last_read_at
    update!(column => Time.current)
  end

  private

  def assign_conversation_id
    return if conversation_id.present?

    self.class.uncached do
      10.times do
        candidate = "conv_#{SecureRandom.alphanumeric(12).downcase}"
        unless self.class.exists?(conversation_id: candidate)
          self.conversation_id = candidate
          return
        end
      end
    end

    raise "Failed to generate unique conversation_id after 10 attempts"
  end
end
