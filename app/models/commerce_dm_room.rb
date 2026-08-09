# frozen_string_literal: true

# A real 1:1 Matrix direct room shared by a (buyer, seller) pair.
#
# WhatsApp-style dedup: no matter how many product conversations a buyer and
# seller have, they share ONE direct room. `commerce_conversations.dm_room_id`
# points here; conversations created later reuse the same room. Neither party
# ever sees the other's Tween/Matrix ID until a DM is accepted — the room is
# created by the relay bot and only joined after consent.
class CommerceDmRoom < ApplicationRecord
  validates :buyer_user_id, :seller_user_id, :matrix_room_id, presence: true
  validates :buyer_user_id, uniqueness: { scope: :seller_user_id, message: "already has a DM room with this seller" }
  validates :matrix_room_id, uniqueness: true
  validates :status, inclusion: { in: %w[active closed] }

  # Find the shared 1:1 room for a pair, or nil.
  def self.for_pair(buyer_user_id, seller_user_id)
    find_by(buyer_user_id: buyer_user_id, seller_user_id: seller_user_id)
  end
end
