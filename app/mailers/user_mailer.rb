# frozen_string_literal: true

class UserMailer < ApplicationMailer
  # Generic notification email dispatched by NotificationDispatcher.
  # @param user [User] recipient
  # @param title [String] email subject + heading
  # @param body [String] plain-text body from the notification
  # @param metadata [Hash] optional deep_link, order_id, etc.
  def notification(user, title, body, metadata: {})
    @user = user
    @title = title
    @body = body
    @deep_link = metadata[:deep_link]
    @metadata = metadata

    mail(
      to: user.email,
      subject: "Tween — #{title}"
    )
  end
end
