# frozen_string_literal: true

# Maps a user to their private Matrix "notification room".
#
# This room is push infrastructure, not a UI surface: the user is a member
# so the Matrix pusher delivers real push for every event published there,
# but the client hides it (m.tween.notifications state) from the chat list.
class UserNotificationRoom < ApplicationRecord
  validates :user_id, :matrix_room_id, presence: true
  validates :user_id, uniqueness: true
end
