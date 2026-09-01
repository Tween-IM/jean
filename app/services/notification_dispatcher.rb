# frozen_string_literal: true

# Unified entry point for all user-facing notifications in Jean.
#
# Every notification — social, commerce, payment, system — flows through
# this class. It handles:
#   1. In-app Notification record (read by the notifications list)
#   2. FCM push notification (direct to device, bypasses Matrix/Sygnal)
#   3. Email (only for money-moving events: commerce + payments)
#
# Usage:
#   NotificationDispatcher.notify(
#     user_id: "@alice:tween.im",
#     source: :commerce,
#     notification_type: :payment,
#     title: "Payment received",
#     body: "You received ₦5,000",
#     deep_link: "tween://orders/ord_123",
#     metadata: { amount: 5000, currency: "NGN" }
#   )
#
class NotificationDispatcher
  # Which channels each source activates by default.
  # Email is restricted to money-moving sources to avoid inbox noise.
  SOURCE_CHANNELS = {
    social:   %i[in_app push],
    commerce: %i[in_app push email],
    tweenpay: %i[in_app push email],
    payment:  %i[in_app push email],
    system:   %i[in_app]
  }.freeze

  def self.notify(**)
    new(**).dispatch
  end

  def initialize(user_id:, source:, notification_type:, title:, body:,
                 target_type: nil, target_id: nil, metadata: {},
                 actor_id: nil, deep_link: nil)
    @user_id = user_id
    @source = source.to_sym
    @notification_type = notification_type.to_s
    @title = title
    @body = body
    @target_type = target_type
    @target_id = target_id
    @metadata = metadata
    @actor_id = actor_id
    @deep_link = deep_link
  end

  def dispatch
    return if @user_id.blank?

    channels = enabled_channels
    create_in_app_notification if channels.include?(:in_app)
    send_push if channels.include?(:push)
    send_email if channels.include?(:email)
  rescue StandardError => e
    Rails.logger.error "[NotificationDispatcher] Failed for #{@user_id}: #{e.message}"
  end

  private

  # Determine which channels are enabled, checking user preferences.
  def enabled_channels
    candidates = SOURCE_CHANNELS.fetch(@source, %i[in_app])
    candidates.select do |channel|
      NotificationPreference.enabled?(@user_id, channel, @notification_type)
    end
  end

  # --- Channel: In-App ---

  def create_in_app_notification
    Notification.create!(
      user_id: @user_id,
      actor_id: @actor_id,
      notification_type: @notification_type,
      source: @source,
      target_type: @target_type,
      target_id: @target_id,
      title: @title,
      body: @body,
      metadata: @metadata
    )
  end

  # --- Channel: Push (FCM) ---

  def send_push
    PushNotificationService.send_push(
      user_id: @user_id,
      title: @title,
      body: @body,
      deep_link: @deep_link,
      data: @metadata.slice(:order_id, :conversation_id, :source)
    )
  end

  # --- Channel: Email ---

  def send_email
    user = User.find_by(matrix_user_id: @user_id)
    return if user.blank? || user.email.blank?

    UserMailer.notification(user, @title, @body, metadata: @metadata).deliver_later
  end
end
