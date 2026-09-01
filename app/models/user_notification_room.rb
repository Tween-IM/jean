# frozen_string_literal: true

# DEPRECATED: This model and the notification room flow are superseded by
# direct FCM push via PushNotificationService. Kept for backward compat
# with existing database records. New notifications use NotificationDispatcher
# which sends FCM push directly — no Matrix room intermediary needed.
#
# Previously: AS created a private room per user, published events there,
# and Synapse routed push via the user's pusher config.
# Now: NotificationDispatcher sends FCM push directly to device tokens
# fetched from the Synapse pushers table.
class UserNotificationRoom < ApplicationRecord
  validates :user_id, :matrix_room_id, presence: true
  validates :user_id, uniqueness: true
end
