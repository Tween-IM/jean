# frozen_string_literal: true

# Direct FCM push notification service for Jean.
# Sends push notifications directly to devices via Firebase Cloud Messaging,
# bypassing Matrix/Sygnal entirely. Used for commerce notifications that
# don't need E2EE encryption (deal accepted, money received, etc.).
#
# FCM credentials are read from the FCM_SERVICE_ACCOUNT_JSON env var
# (a JSON string containing the Google service account key).
#
# FCM tokens are fetched from the Synapse database (pushers table)
# via a direct PG connection (not through ActiveRecord).
class PushNotificationService
  FCM_URL = "https://fcm.googleapis.com/v1/projects/%{project_id}/messages:send"
  PROJECT_ID = ENV.fetch("FCM_PROJECT_ID", "tween-b222a")
  SYNAPSE_DB_HOST = ENV.fetch("SYNAPSE_DB_HOST", "matrix-postgres")
  SYNAPSE_DB_NAME = ENV.fetch("SYNAPSE_DB_NAME", "synapse")
  SYNAPSE_DB_USER = ENV.fetch("SYNAPSE_DB_USER", "synapse")
  SYNAPSE_DB_PASSWORD = ENV.fetch("SYNAPSE_DB_PASSWORD", nil)

  class << self
    # Send a push notification directly to a user's FCM token(s).
    # @param user_id [String] Matrix user ID (e.g. "@mona:tween.im")
    # @param title [String] Notification title
    # @param body [String] Notification body
    # @param deep_link [String] Deep link URL (e.g. "tween://orders/ord_123")
    # @param data [Hash] Additional data to include in the push payload
    def send_push(user_id:, title:, body:, deep_link: nil, data: {})
      tokens = fetch_fcm_tokens(user_id)
      if tokens.empty?
        Rails.logger.info "[PushNotificationService] No FCM tokens for #{user_id}"
        return
      end

      tokens.each do |token|
        send_fcm_notification(
          token: token,
          title: title,
          body: body,
          deep_link: deep_link,
          data: data
        )
      end
    rescue StandardError => e
      Rails.logger.error "[PushNotificationService] Failed to send push to #{user_id}: #{e.message}"
    end

    private

    # Fetch FCM tokens for a user from the Synapse pushers table.
    # Uses a direct PG connection to the Synapse database.
    # Returns an array of FCM pushkey strings.
    def fetch_fcm_tokens(user_id)
      require "pg"

      conn = PG.connect(
        "host=#{SYNAPSE_DB_HOST} dbname=#{SYNAPSE_DB_NAME} user=#{SYNAPSE_DB_USER} password=#{SYNAPSE_DB_PASSWORD}"
      )

      result = conn.exec_params(
        "SELECT pushkey FROM pushers WHERE user_name = $1 AND app_id = 'com.ruut.tweenchat'",
        [user_id]
      )

      result.map { |row| row["pushkey"] }.compact
    rescue StandardError => e
      Rails.logger.error "[PushNotificationService] Failed to fetch FCM tokens for #{user_id}: #{e.message}"
      []
    ensure
      conn&.close
    end

    # Send an FCM v1 notification message using Faraday.
    def send_fcm_notification(token:, title:, body:, deep_link: nil, data: {})
      auth_token = get_fcm_auth_token
      return if auth_token.nil?

      url = format(FCM_URL, project_id: PROJECT_ID)

      message = {
        message: {
          token: token,
          notification: {
            title: title,
            body: body
          },
          data: {
            title: title,
            body: body,
            deep_link: deep_link.to_s,
            **data
          }.compact,
          apns: {
            headers: {
              "apns-push-type" => "alert",
              "apns-priority" => "10"
            },
            payload: {
              aps: {
                alert: {
                  title: title,
                  body: body
                },
                sound: "default",
                "mutable-content" => 1,
                "content-available" => 1
              }
            }
          }
        }
      }

      response = Faraday.post(url) do |req|
        req.headers["Authorization"] = "Bearer #{auth_token}"
        req.headers["Content-Type"] = "application/json"
        req.body = message.to_json
      end

      if response.success?
        Rails.logger.info "[PushNotificationService] Push sent to #{token[0..8]}...: #{title}"
      else
        Rails.logger.error "[PushNotificationService] FCM error: #{response.status} #{response.body}"
      end
    rescue StandardError => e
      Rails.logger.error "[PushNotificationService] Failed to send FCM: #{e.message}"
    end

    # Get FCM auth token using the service account credentials from env var.
    # Uses google-auth library to generate a signed JWT and exchange it for
    # an access token.
    def get_fcm_auth_token
      require "googleauth"

      json_key = ENV["FCM_SERVICE_ACCOUNT_JSON"]
      if json_key.blank?
        Rails.logger.error "[PushNotificationService] FCM_SERVICE_ACCOUNT_JSON env var not set"
        return nil
      end

      credentials = Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: StringIO.new(json_key),
        scope: "https://www.googleapis.com/auth/firebase.messaging"
      )

      credentials.fetch_access_token!
      credentials.access_token
    rescue StandardError => e
      Rails.logger.error "[PushNotificationService] Failed to get FCM auth token: #{e.message}"
      nil
    end
  end
end
