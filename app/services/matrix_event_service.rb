class MatrixEventService
  # TMCP Protocol Section 8: Event System
  # Updated for v1.5.0 with Payment Bot integration

  MATRIX_API_URL = ENV["MATRIX_API_URL"] || "https://matrix.example.com"
  MATRIX_ACCESS_TOKEN = ENV["MATRIX_ACCESS_TOKEN"]

  class << self
    def payment_bot
      @payment_bot ||= PaymentBotService.new
    end

    def publish_payment_completed(payment_data)
      room_id = payment_data[:room_id] || get_user_room(payment_data[:user_id])

      payment_bot.send_payment_completed(
        room_id: room_id,
        payment_data: {
          payment_id: payment_data[:payment_id],
          txn_id: payment_data[:txn_id],
          amount: payment_data[:amount],
          currency: payment_data[:currency],
          sender_user_id: payment_data[:sender_user_id],
          sender_display_name: payment_data[:sender_display_name],
          sender_avatar_url: payment_data[:sender_avatar_url],
          recipient_user_id: payment_data[:recipient_user_id],
          recipient_display_name: payment_data[:recipient_display_name],
          recipient_avatar_url: payment_data[:recipient_avatar_url],
          note: payment_data[:note],
          timestamp: payment_data[:timestamp]
        }
      )
    end

    def publish_payment_sent(payment_data)
      room_id = payment_data[:room_id] || get_user_room(payment_data[:user_id])

      payment_bot.send_payment_sent(
        room_id: room_id,
        payment_data: {
          payment_id: payment_data[:payment_id],
          txn_id: payment_data[:txn_id],
          amount: payment_data[:amount],
          currency: payment_data[:currency],
          sender_user_id: payment_data[:sender_user_id],
          sender_display_name: payment_data[:sender_display_name],
          sender_avatar_url: payment_data[:sender_avatar_url],
          recipient_user_id: payment_data[:recipient_user_id],
          recipient_display_name: payment_data[:recipient_display_name],
          recipient_avatar_url: payment_data[:recipient_avatar_url],
          note: payment_data[:note],
          timestamp: payment_data[:timestamp]
        }
      )
    end

    def publish_payment_failed(payment_data)
      room_id = payment_data[:room_id] || get_user_room(payment_data[:user_id])

      payment_bot.send_payment_failed(
        room_id: room_id,
        payment_data: {
          txn_id: payment_data[:txn_id],
          amount: payment_data[:amount],
          currency: payment_data[:currency],
          sender_user_id: payment_data[:sender_user_id],
          sender_display_name: payment_data[:sender_display_name],
          recipient_user_id: payment_data[:recipient_user_id],
          recipient_display_name: payment_data[:recipient_display_name],
          error_code: payment_data[:error_code],
          error_message: payment_data[:error_message],
          timestamp: payment_data[:timestamp]
        }
      )
    end

    def publish_payment_refunded(payment_data)
      room_id = payment_data[:room_id] || get_user_room(payment_data[:user_id])

      payment_bot.send_payment_refunded(
        room_id: room_id,
        payment_data: {
          original_txn_id: payment_data[:original_txn_id],
          refund_txn_id: payment_data[:refund_txn_id],
          amount: payment_data[:amount],
          currency: payment_data[:currency],
          sender_user_id: payment_data[:sender_user_id],
          sender_display_name: payment_data[:sender_display_name],
          recipient_user_id: payment_data[:recipient_user_id],
          recipient_display_name: payment_data[:recipient_display_name],
          reason: payment_data[:reason],
          timestamp: payment_data[:timestamp]
        }
      )
    end

    def publish_p2p_transfer(transfer_data)
      sender = transfer_data["sender"] || transfer_data[:sender]
      recipient = transfer_data["recipient"] || transfer_data[:recipient]

      event = {
        type: "m.tween.wallet.p2p",
        content: {
          msgtype: "m.tween.money",
          body: "💸 Sent #{transfer_data['amount'] || transfer_data[:amount]} #{transfer_data['currency'] || transfer_data[:currency]}",
          transfer_id: transfer_data["transfer_id"] || transfer_data[:transfer_id],
          amount: transfer_data["amount"] || transfer_data[:amount],
          currency: transfer_data["currency"] || transfer_data[:currency],
          note: transfer_data["note"] || transfer_data[:note],
          sender: { user_id: sender["user_id"] || sender[:user_id] },
          recipient: { user_id: recipient["user_id"] || recipient[:user_id] },
          status: transfer_data["status"] || transfer_data[:status],
          timestamp: transfer_data["timestamp"] || transfer_data[:timestamp]
        },
        room_id: transfer_data["room_id"] || transfer_data[:room_id]
      }

      publish_event(event)
    end

    def publish_p2p_status_update(transfer_id, status, details = {})
      event = {
        type: "m.tween.wallet.p2p.status",
        content: {
          transfer_id: transfer_id,
          status: status,
          timestamp: Time.current.iso8601
        }.merge(details)
      }

      event[:room_id] = details[:room_id] || get_default_room

      publish_event(event)
    end

    def publish_gift_created(gift_data)
      event = {
        type: "m.tween.gift",
        content: {
          msgtype: "m.tween.gift",
          body: "🎁 Gift: #{gift_data['total_amount']} #{gift_data['currency']}",
          gift_id: gift_data["gift_id"],
          type: gift_data["type"],
          total_amount: gift_data["total_amount"],
          count: gift_data["count"],
          message: gift_data["message"],
          status: "active",
          opened_count: 0,
          actions: [
            {
              type: "open",
              label: "Open Gift",
              endpoint: "/api/v1/gifts/#{gift_data['gift_id']}/open"
            }
          ]
        },
        room_id: gift_data["room_id"]
      }

      publish_event(event)
    end

    def publish_gift_opened(gift_id, opened_data)
      event = {
        type: "m.tween.gift.opened",
        content: {
          gift_id: gift_id,
          opened_by: opened_data["user_id"],
          amount: opened_data["amount"],
          opened_at: opened_data["opened_at"],
          remaining_count: opened_data["remaining_count"],
          leaderboard: opened_data["leaderboard"] || []
        },
        room_id: opened_data["room_id"]
      }

      publish_event(event)
    end

    def publish_miniapp_lifecycle_event(event_type, app_data, user_id, room_id = nil)
      event_content = case event_type
      when "launch"
        {
          miniapp_id: app_data["app_id"],
          launch_source: app_data["launch_source"] || "user_initiated",
          launch_params: app_data["launch_params"] || {},
          session_id: app_data["session_id"] || SecureRandom.uuid
        }
      when "install"
        {
          miniapp_id: app_data["app_id"],
          version: app_data["version"],
          user_id: user_id
        }
      when "update"
        {
          miniapp_id: app_data["app_id"],
          old_version: app_data["old_version"],
          new_version: app_data["new_version"],
          user_id: user_id
        }
      when "uninstall"
        {
          miniapp_id: app_data["app_id"],
          version: app_data["version"],
          user_id: user_id
        }
      end

      event = {
        type: "m.tween.miniapp.#{event_type}",
        content: event_content,
        room_id: room_id || get_user_room(user_id)
      }

      publish_event(event)
    end

    def publish_authorization_event(miniapp_id, user_id, authorized, details = {})
      event = {
        type: "m.room.tween.authorization",
        state_key: miniapp_id,
        content: {
          authorized: authorized,
          timestamp: Time.current.to_i,
          user_id: user_id,
          miniapp_id: miniapp_id
        }.merge(details)
      }

      event[:room_id] = details[:room_id] || details["room_id"] || get_default_room

      publish_event(event)
    end

    private

    def publish_event(event_data)
      return unless MATRIX_ACCESS_TOKEN

      begin
        uri = URI("#{MATRIX_API_URL}/_matrix/client/v3/rooms/#{event_data[:room_id]}/send/m.room.message")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{MATRIX_ACCESS_TOKEN}"
        request["Content-Type"] = "application/json"
        request.body = event_data.to_json

        response = http.request(request)

        if response.code.to_i == 200
          Rails.logger.info "Matrix event published: #{event_data[:type]}"
          JSON.parse(response.body)["event_id"]
        else
          Rails.logger.error "Failed to publish Matrix event: #{response.body}"
          nil
        end
      rescue => e
        Rails.logger.error "Matrix event publishing error: #{e.message}"
        nil
      end
    end

    def get_user_room(user_id)
      "!general:matrix.example"
    end

    def get_default_room
      "!tmcp:matrix.example"
    end
  end
end
