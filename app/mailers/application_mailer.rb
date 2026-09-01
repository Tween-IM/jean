class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM", "noreply@tween.im")
  layout "mailer"

  include Rails.application.routes.url_helpers

  default_url_options[:host] = ENV.fetch("APP_HOST", "tween.im")
  default_url_options[:protocol] = ENV.fetch("APP_PROTOCOL", "https")
end
