# frozen_string_literal: true

class NotificationPreference < ApplicationRecord
  CHANNELS = %w[in_app push email].freeze
  TYPES = %w[all social commerce payment system].freeze

  validates :user_id, presence: true
  validates :channel, presence: true, inclusion: { in: CHANNELS }
  validates :notification_type, presence: true, inclusion: { in: TYPES }
  validates :user_id, uniqueness: { scope: [ :channel, :notification_type ] }

  scope :for_user, ->(user_id) { where(user_id: user_id) }

  # Returns true if the given channel+type combination is enabled.
  # Falls back to "all" type if no specific type override exists.
  # Returns true (enabled by default) if no preference record exists.
  def self.enabled?(user_id, channel, notification_type)
    specific = find_by(user_id: user_id, channel: channel, notification_type: notification_type.to_s)
    return specific.enabled if specific

    general = find_by(user_id: user_id, channel: channel, notification_type: "all")
    general.nil? || general.enabled?
  end
end
