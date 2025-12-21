class MatrixEventService
  # TMCP Protocol Section 8: Event System
  # Handles publishing Matrix events for TMCP operations

  MATRIX_API_URL = ENV["MATRIX_API_URL"] || "https://matrix.example.com"
  MATRIX_ACCESS_TOKEN = ENV["MATRIX_ACCESS_TOKEN"]

  class << self
    # Publish payment completed event (PROTO Section 8.1.2)
    def publish_payment_completed(payment_data)
      event = {
        type: "m.tween.payment.completed",
        content: {
          msgtype: "m.tween.payment",
          body: "Payment of #{payment_data['amount']} #{payment_data['currency']} completed",
          payment_id: payment_data["payment_id"],
          txn_id: payment_data["txn_id"],
          amount: payment_data["amount"],
          merchant: payment_data["merchant"],
          status: "completed"
        },
        room_id: payment_data["room_id"] || get_user_room(payment_data["user_id"])
      }

      publish_event(event)
    end

    # Publish P2P transfer event (PROTO Section 7.2.2)
    def publish_p2p_transfer(transfer_data)
      event = {
        type: "m.tween.wallet.p2p",
        content: {
          msgtype: "m.tween.money",
          body: "💸 Sent #{transfer_data['amount']} #{transfer_data['currency']}",
          transfer_id: transfer_data["transfer_id"],
          amount: transfer_data["amount"],
          currency: transfer_data["currency"],
          note: transfer_data["note"],
          sender: { user_id: transfer_data["sender"]["user_id"] },
          recipient: { user_id: transfer_data["recipient"]["user_id"] },
          status: transfer_data["status"],
          timestamp: transfer_data["timestamp"]
        },
        room_id: transfer_data["room_id"]
      }

      publish_event(event)
    end

    # Publish P2P transfer status update (PROTO Section 7.2.2)
    def publish_p2p_status_update(transfer_id, status, details = {})
      event = {
        type: "m.tween.wallet.p2p.status",
        content: {
          transfer_id: transfer_id,
          status: status,
          timestamp: Time.current.iso8601
        }.merge(details)
      }

      # Find room from transfer data (would need to be passed or cached)
      # For now, assume it's available in details
      event[:room_id] = details[:room_id] || get_default_room

      publish_event(event)
    end

    # Publish group gift creation event (PROTO Section 7.5.4)
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

    # Publish gift opened event (PROTO Section 7.5.4)
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

    # Publish mini-app lifecycle events (PROTO Section 8.1.4)
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

    # Publish authorization events (PROTO Section 5.3)
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
      # In production, this would query user's default room
      # For demo, return a default room
      "!general:matrix.example"
    end

    def get_default_room
      "!tmcp:matrix.example"
    end
  end
end
