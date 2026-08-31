# frozen_string_literal: true

class MatrixEventService
  # TMCP Protocol Section 8: Event System
  # Updated for v1.5.0 with Payment Bot integration

  MATRIX_API_URL = ENV["MATRIX_API_URL"] || "https://matrix.example.com"
  MATRIX_ACCESS_TOKEN = ENV["MATRIX_ACCESS_TOKEN"]

  # Default sender for bot-initiated events (when no user sender is specified)
  # Domain must match Synapse server_name (tween.im) or AS registration users regex.
  DEFAULT_SENDER = "@_tmcp_payments:tween.im".freeze
  SOCIAL_BOT_USER = "@_tmcp_social:tween.im".freeze
  COMMERCE_BOT_USER = "@_tmcp_commerce:tween.im".freeze

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
      publish_event(p2p_transfer_event(transfer_data))
    end

    # Synchronous variant used by the wallet confirm controller so the in-chat
    # PaymentCard lands in the room before the confirm response returns —
    # no dependency on the async job queue for real-time feedback.
    def publish_p2p_transfer_now!(transfer_data)
      _publish_event_sync(p2p_transfer_event(transfer_data))
    end

    def p2p_transfer_event(transfer_data)
      sender = transfer_data["sender"] || transfer_data[:sender]
      recipient = transfer_data["recipient"] || transfer_data[:recipient]
      status = transfer_data["status"] || transfer_data[:status]
      recipient_acceptance_required = ActiveModel::Type::Boolean.new.cast(
        transfer_data["recipient_acceptance_required"] || transfer_data[:recipient_acceptance_required]
      )

      room_id = transfer_data["room_id"] || transfer_data[:room_id]
      return unless room_id

      # Convert amount to string to avoid JSON float issues with Matrix
      amount = transfer_data["amount"] || transfer_data[:amount]
      amount_cents = (amount.to_f * 100).to_i if amount

      # Get sender's display name for the body text
      sender_display_name = sender["display_name"] || sender[:display_name] ||
                           (sender["user_id"] || sender[:user_id]).to_s.split(":").first.gsub("@", "")

      # Ensure currency is never empty - default to NGN for test environment
      currency = transfer_data["currency"] || transfer_data[:currency]
      currency = "NGN" if currency.nil? || currency.to_s.empty?

      event = {
        type: "m.tween.wallet.p2p",
        room_id: room_id,
        # Use sender's user_id so the event appears to come from the actual sender, not the bot
        sender_id: sender["user_id"] || sender[:user_id],
        content: {
          msgtype: "m.tween.money",
          body: "💸 #{sender_display_name} sent #{amount} #{currency}",
          transfer_id: transfer_data["transfer_id"] || transfer_data[:transfer_id],
          amount: amount.to_s,
          amount_cents: amount_cents,
          currency: currency,
          note: transfer_data["note"] || transfer_data[:note],
          sender: {
            user_id: sender["user_id"] || sender[:user_id],
            display_name: sender["display_name"] || sender[:display_name]
          },
          recipient: {
            user_id: recipient["user_id"] || recipient[:user_id],
            display_name: recipient["display_name"] || recipient[:display_name]
          },
          status: status,
          recipient_acceptance_required: recipient_acceptance_required,
          timestamp: transfer_data["timestamp"] || transfer_data[:timestamp]
        }
      }

      event
    end

    # Commerce relay-chat push: publish a lightweight event to the recipient's
    # private notification room so Synapse → Sygnal delivers a real push.
    # The recipient is a member of their notification room; the relay room
    # stays bot-only for privacy.
    def publish_commerce_inquiry(recipient_user_id:, conversation_id:, label:, body:)
      room_id = get_user_room(recipient_user_id)
      return unless room_id

      publish_event(
        type: "m.room.message",
        room_id: room_id,
        sender_id: "@_tmcp:tween.im",
        content: {
          msgtype: "m.tween.commerce",
          body: "New message from #{label}: #{body.to_s.truncate(120)}",
          conversation_id: conversation_id,
          label: label,
          deep_link: "tween://commerce/conversation/#{conversation_id}"
        }
      )
    end

    # Push a structured deal notification into a user's private notification
    # room, so Synapse → Sygnal delivers a real push. Published as m.room.message
    # (not a custom event type) so it matches the default push rule; the
    # structured content rides in the msgtype/body. Used for protected-deal
    # lifecycle events (offer, funding, shipped, dispute, release, refund).
    def publish_commerce_notification(user_id:, event_type:, title:, body:, deep_link:, order_id: nil, conversation_id: nil)
      room_id = get_user_room(user_id)
      return unless room_id

      publish_event(
        type: "m.room.message",
        room_id: room_id,
        sender_id: "@_tmcp:tween.im",
        content: {
          msgtype: event_type,
          body: body.to_s.truncate(200),
          title: title,
          body_plain: body.to_s.truncate(200),
          order_id: order_id,
          conversation_id: conversation_id,
          deep_link: deep_link
        }.compact
      )
    end

    def publish_p2p_status_update(transfer_id, status, details = {})
      visual_details = case status
      when "completed"
        {
          icon: "✓",
          color: "green",
          status_text: "Accepted"
        }
      when "rejected"
        {
          icon: "✕",
          color: "red",
          status_text: "Declined"
        }
      when "expired"
        {
          icon: "⏰",
          color: "gray",
          status_text: "Expired"
        }
      else
        {
          icon: "⏳",
          color: "yellow",
          status_text: status
        }
      end

      event = {
        type: "m.tween.wallet.p2p.status",
        sender_id: DEFAULT_SENDER,
        content: {
          transfer_id: transfer_id,
          status: status,
          timestamp: Time.current.iso8601,
          visual: visual_details
        }.merge(details)
      }

      event[:room_id] = details[:room_id] || get_default_room

      publish_event(event)
    end

    def publish_gift_created(gift_data)
      event = {
        type: "m.tween.gift",
        sender_id: gift_data["creator_user_id"] || gift_data[:creator_user_id] || DEFAULT_SENDER,
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
        sender_id: opened_data["user_id"] || opened_data[:user_id] || DEFAULT_SENDER,
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
        sender_id: user_id || DEFAULT_SENDER,
        content: event_content,
        room_id: room_id || get_user_room(user_id)
      }

      publish_event(event)
    end

    def publish_post_published(post_data)
      event = {
        type: "m.tween.social.post.published",
        sender_id: post_data["creator_id"] || post_data[:creator_id] || SOCIAL_BOT_USER,
        content: {
          msgtype: "m.tween.social.post",
          body: "New post: #{post_data['caption'] || post_data[:caption] || 'Post'}",
          post_id: post_data["post_id"] || post_data[:post_id] || post_data["video_id"] || post_data[:video_id],
          content_type: post_data["content_type"] || post_data[:content_type],
          creator_id: post_data["creator_id"] || post_data[:creator_id],
          thumbnail_url: post_data["thumbnail_url"] || post_data[:thumbnail_url],
          published_at: post_data["published_at"] || post_data[:published_at] || Time.current.iso8601
        },
        room_id: post_data["room_id"] || post_data[:room_id] || get_default_room
      }

      publish_event(event)
    end

    alias_method :publish_video_published, :publish_post_published

    def publish_post_deleted(post_data)
      event = {
        type: "m.tween.social.post.deleted",
        sender_id: SOCIAL_BOT_USER,
        content: {
          post_id: post_data["post_id"] || post_data[:post_id] || post_data["video_id"] || post_data[:video_id],
          creator_id: post_data["creator_id"] || post_data[:creator_id],
          deleted_at: post_data["deleted_at"] || post_data[:deleted_at] || Time.current.iso8601
        },
        room_id: post_data["room_id"] || post_data[:room_id] || get_default_room
      }

      publish_event(event)
    end

    alias_method :publish_video_deleted, :publish_post_deleted

    def publish_post_liked(like_data)
      event = {
        type: "m.tween.social.post.liked",
        sender_id: like_data["user_id"] || like_data[:user_id] || DEFAULT_SENDER,
        content: {
          post_id: like_data["post_id"] || like_data[:post_id] || like_data["video_id"] || like_data[:video_id],
          user_id: like_data["user_id"] || like_data[:user_id],
          created_at: like_data["created_at"] || like_data[:created_at] || Time.current.iso8601
        },
        room_id: like_data["room_id"] || like_data[:room_id] || get_user_room(like_data["creator_id"] || like_data[:creator_id])
      }

      publish_event(event)
    end

    alias_method :publish_like_created, :publish_post_liked

    def publish_post_commented(comment_data)
      event = {
        type: "m.tween.social.post.commented",
        sender_id: comment_data["author_id"] || comment_data[:author_id] || DEFAULT_SENDER,
        content: {
          msgtype: "m.tween.social.comment",
          body: comment_data["body"] || comment_data[:body],
          post_id: comment_data["post_id"] || comment_data[:post_id] || comment_data["video_id"] || comment_data[:video_id],
          comment_id: comment_data["comment_id"] || comment_data[:comment_id],
          author_id: comment_data["author_id"] || comment_data[:author_id],
          created_at: comment_data["created_at"] || comment_data[:created_at] || Time.current.iso8601
        },
        room_id: comment_data["room_id"] || comment_data[:room_id] || get_user_room(comment_data["creator_id"] || comment_data[:creator_id])
      }

      publish_event(event)
    end

    alias_method :publish_comment_created, :publish_post_commented

    def publish_follow_created(follow_data)
      event = {
        type: "m.tween.social.follow.created",
        sender_id: follow_data["follower_id"] || follow_data[:follower_id] || DEFAULT_SENDER,
        content: {
          follower_id: follow_data["follower_id"],
          creator_id: follow_data["creator_id"],
          created_at: follow_data["created_at"] || Time.current.iso8601
        },
        room_id: follow_data["room_id"] || get_user_room(follow_data["creator_id"] || follow_data[:creator_id])
      }

      publish_event(event)
    end

    def publish_post_moderated(moderation_data)
      event = {
        type: "m.tween.social.post.moderated",
        sender_id: SOCIAL_BOT_USER,
        content: {
          post_id: moderation_data["post_id"] || moderation_data[:post_id] || moderation_data["video_id"] || moderation_data[:video_id],
          moderation_status: moderation_data["moderation_status"] || moderation_data[:moderation_status],
          creator_id: moderation_data["creator_id"] || moderation_data[:creator_id],
          message: moderation_data["message"] || moderation_data[:message],
          updated_at: moderation_data["updated_at"] || moderation_data[:updated_at] || Time.current.iso8601
        },
        room_id: moderation_data["room_id"] || moderation_data[:room_id] || get_user_room(moderation_data["creator_id"] || moderation_data[:creator_id])
      }

      publish_event(event)
    end

    alias_method :publish_moderation_updated, :publish_post_moderated

    def publish_order_created(order_data)
      event = {
        type: "m.tween.commerce.order.created",
        sender_id: COMMERCE_BOT_USER,
        content: {
          msgtype: "m.tween.commerce.order",
          order_id: order_data["order_id"],
          payment_id: order_data["payment_id"],
          merchant_id: order_data["merchant_id"],
          buyer_user_id: order_data["buyer_user_id"],
          status: order_data["status"],
          total: order_data["total"],
          created_at: order_data["created_at"] || Time.current.iso8601
        },
        room_id: order_data["room_id"] || get_user_room(order_data["buyer_user_id"] || order_data[:buyer_user_id])
      }

      publish_event(event)
    end

    def publish_order_updated(order_data)
      event = {
        type: "m.tween.commerce.order.updated",
        sender_id: COMMERCE_BOT_USER,
        content: {
          order_id: order_data["order_id"],
          status: order_data["status"],
          fulfillment_status: order_data["fulfillment_status"],
          updated_at: order_data["updated_at"] || Time.current.iso8601
        },
        room_id: order_data["room_id"] || get_user_room(order_data["buyer_user_id"] || order_data[:buyer_user_id])
      }

      publish_event(event)
    end

    def publish_checkout_created(checkout_data)
      event = {
        type: "m.tween.commerce.checkout.created",
        sender_id: COMMERCE_BOT_USER,
        content: {
          checkout_id: checkout_data["checkout_id"],
          cart_id: checkout_data["cart_id"],
          merchant_id: checkout_data["merchant_id"],
          buyer_user_id: checkout_data["buyer_user_id"],
          expires_at: checkout_data["expires_at"],
          created_at: checkout_data["created_at"] || Time.current.iso8601
        },
        room_id: checkout_data["room_id"] || get_user_room(checkout_data["buyer_user_id"] || checkout_data[:buyer_user_id])
      }

      publish_event(event)
    end

    def publish_refund_updated(refund_data)
      event = {
        type: "m.tween.commerce.refund.updated",
        sender_id: COMMERCE_BOT_USER,
        content: {
          refund_id: refund_data["refund_id"],
          order_id: refund_data["order_id"],
          amount: refund_data["amount"],
          status: refund_data["status"],
          reason: refund_data["reason"],
          updated_at: refund_data["updated_at"] || Time.current.iso8601
        },
        room_id: refund_data["room_id"] || get_user_room(refund_data["buyer_user_id"] || refund_data[:buyer_user_id])
      }

      publish_event(event)
    end

    def publish_authorization_event(miniapp_id, user_id, authorized, details = {})
      event = {
        type: "m.room.tween.authorization",
        state_key: miniapp_id,
        sender_id: user_id || DEFAULT_SENDER,
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

    # ============================================================================
    # Protected commerce (Tween Buyer Protection)
    #
    # Backend-owned events published as m.room.message so normal push, unread
    # and room-ordering behavior apply. Clients reconcile against Jean/Tween
    # Pay on open; Matrix is never the financial database.
    # ============================================================================

    def publish_offer_event(offer_data, event_type: "m.tween.commerce.offer")
      event = {
        type: event_type,
        sender_id: COMMERCE_BOT_USER,
        content: {
          msgtype: "m.tween.commerce.offer",
          offer_id: offer_data[:offer_id],
          conversation_id: offer_data[:conversation_id],
          offer_type: offer_data[:offer_type],
          version: offer_data[:version],
          status: offer_data[:status],
          currency: offer_data[:currency],
          total_cents: offer_data[:total_cents],
          seller_proceeds_cents: offer_data[:seller_proceeds_cents],
          order_id: offer_data[:order_id],
          expires_at: offer_data[:expires_at],
          created_at: offer_data[:created_at] || Time.current.iso8601
        },
        room_id: offer_data[:room_id]
      }

      publish_event(event)
    end

    def publish_protected_payment_event(event_type, payment_data)
      event = {
        type: event_type,
        sender_id: COMMERCE_BOT_USER,
        content: {
          msgtype: "m.tween.commerce.payment",
          protected_payment_id: payment_data[:protected_payment_id],
          order_id: payment_data[:order_id],
          status: payment_data[:status],
          currency: payment_data[:currency],
          gross_amount_cents: payment_data[:gross_amount_cents],
          released_amount_cents: payment_data[:released_amount_cents],
          refunded_amount_cents: payment_data[:refunded_amount_cents],
          updated_at: payment_data[:updated_at] || Time.current.iso8601
        },
        room_id: payment_data[:room_id]
      }

      publish_event(event)
    end

    def publish_fulfilment_updated(fulfilment_data)
      event = {
        type: "m.tween.commerce.fulfilment.updated",
        sender_id: COMMERCE_BOT_USER,
        content: {
          msgtype: "m.tween.commerce.fulfilment",
          fulfillment_id: fulfilment_data[:fulfillment_id],
          order_id: fulfilment_data[:order_id],
          kind: fulfilment_data[:kind],
          status: fulfilment_data[:status],
          tracking_number: fulfilment_data[:tracking_number],
          updated_at: Time.current.iso8601
        }.compact,
        room_id: fulfilment_data[:room_id]
      }

      publish_event(event)
    end

    def publish_delivery_confirmed(delivery_data)
      event = {
        type: "m.tween.commerce.delivery.confirmed",
        sender_id: COMMERCE_BOT_USER,
        content: {
          msgtype: "m.tween.commerce.fulfilment",
          order_id: delivery_data[:order_id],
          fulfillment_id: delivery_data[:fulfillment_id],
          inspection_deadline: delivery_data[:inspection_deadline],
          updated_at: Time.current.iso8601
        }.compact,
        room_id: delivery_data[:room_id]
      }

      publish_event(event)
    end

    def publish_inspection_started(inspection_data)
      event = {
        type: "m.tween.commerce.inspection.started",
        sender_id: COMMERCE_BOT_USER,
        content: {
          msgtype: "m.tween.commerce.fulfilment",
          order_id: inspection_data[:order_id],
          inspection_deadline: inspection_data[:inspection_deadline],
          updated_at: Time.current.iso8601
        }.compact,
        room_id: inspection_data[:room_id]
      }

      publish_event(event)
    end

    def publish_dispute_opened(dispute_data)
      event = {
        type: "m.tween.commerce.dispute.opened",
        sender_id: COMMERCE_BOT_USER,
        content: {
          msgtype: "m.tween.commerce.dispute",
          dispute_id: dispute_data[:dispute_id],
          order_id: dispute_data[:order_id],
          reason: dispute_data[:reason],
          status: dispute_data[:status],
          updated_at: Time.current.iso8601
        }.compact,
        room_id: dispute_data[:room_id]
      }

      publish_event(event)
    end

    private

    # Publish event using Application Service identity assertion
    # AS uses as_token as access_token and user_id query param to masquerade
    # Events appear to come from the actual sender (Alice/Bob), not the bot
    def publish_event(event_data)
      # Enqueue to background job for reliability and to avoid blocking requests
      if Rails.env.test?
        _publish_event_sync(event_data)
      else
        PublishMatrixEventJob.perform_later(event_data.deep_stringify_keys)
      end
    end

    def _publish_event_sync(event_data)
      # Use AS token for authentication (not user access token)
      as_token = ENV["MATRIX_AS_TOKEN"]
      return unless as_token

      room_id = event_data[:room_id] || event_data["room_id"]
      return unless room_id

      # Determine sender - use explicit sender_id from event_data, or extract from content
      # This makes events appear to come from the actual sender (Alice/Bob), not the bot
      sender_id = event_data[:sender_id] ||
                  event_data["sender_id"] ||
                  event_data.dig(:content, :sender, :user_id) ||
                  event_data.dig("content", "sender", "user_id")

      # Fall back to default sender if none found
      sender_id = DEFAULT_SENDER if sender_id.nil?

      event_type = event_data[:type] || event_data["type"]
      content = event_data[:content] || event_data["content"]

      begin
        # Build URI with user_id query param for identity assertion
        # The AS sends the event on behalf of the actual user (Alice/Bob)
        uri = URI("#{MATRIX_API_URL}/_matrix/client/v3/rooms/#{room_id}/send/#{event_type}")
        uri.query = URI.encode_www_form({ "user_id" => sender_id })

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.open_timeout = 10
        http.read_timeout = 15

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{as_token}"
        request["Content-Type"] = "application/json"
        request.body = content.to_json

        response = http.request(request)

        if response.code.to_i == 200
          Rails.logger.info "Matrix event published: #{event_type} to room #{room_id}"
          JSON.parse(response.body)["event_id"]
        else
          Rails.logger.error "Failed to publish Matrix event: #{response.code} - #{response.body}"
          raise "Matrix event publish failed: #{response.code}"
        end
      rescue => e
        Rails.logger.error "Matrix event publishing error: #{e.message}"
        raise
      end
    end

    def get_user_room(user_id)
      return nil unless user_id

      matrix_domain = ENV.fetch("MATRIX_DOMAIN", "tween.im")
      room_id = find_or_create_user_room(user_id, matrix_domain)
      room_id || get_default_room
    end

    def get_default_room
      ENV.fetch("MATRIX_DEFAULT_ROOM", nil)
    end

    def find_or_create_user_room(user_id, domain)
      as_token = ENV["MATRIX_AS_TOKEN"]
      return nil unless as_token

      record = ::UserNotificationRoom.find_by(user_id: user_id)
      if record&.matrix_room_id
        # Existing notification rooms were created with trusted_private_chat
        # (E2EE), which the push gateway can't decrypt — so pushes showed a
        # generic "New message". Migrate them to a plaintext (private_chat)
        # notification room so the real content is delivered.
        return migrate_notification_room_if_encrypted(user_id, record, domain, as_token)
      end

      room_id = create_notification_room(user_id, domain, as_token)
      return nil unless room_id

      ::UserNotificationRoom.create!(user_id: user_id, matrix_room_id: room_id)
      room_id
    rescue StandardError => e
      Rails.logger.error "Failed to resolve user room: #{e.message}"
      nil
    end
    public :find_or_create_user_room

    # If the user's notification room is E2EE-encrypted, create a fresh
    # unencrypted one (private_chat) and re-point the record. Returns the
    # room id to use, or the existing id when it is already plaintext.
    def migrate_notification_room_if_encrypted(user_id, record, domain, as_token)
      return record.matrix_room_id unless room_encrypted?(record.matrix_room_id)

      new_room_id = create_notification_room(user_id, domain, as_token)
      return record.matrix_room_id unless new_room_id

      record.update!(matrix_room_id: new_room_id)
      Rails.logger.info "Migrated encrypted notification room for #{user_id} -> #{new_room_id}"
      new_room_id
    end

    def room_encrypted?(room_id)
      return false if room_id.blank?
      return false unless ENV["MATRIX_AS_TOKEN"]

      uri = URI("#{MATRIX_API_URL}/_matrix/client/v3/rooms/#{CGI.escape(room_id)}/state/m.room.encryption")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 10
      http.read_timeout = 15

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{ENV['MATRIX_AS_TOKEN']}"
      response = http.request(request)
      response.code.to_i == 200
    rescue StandardError => e
      Rails.logger.warn "Failed to check encryption state for #{room_id}: #{e.message}"
      false
    end

    # Create a private 1:1 between the AS bot and [user_id], inviting them so
    # the client auto-joins and the Matrix pusher can deliver real push.
    # Marked m.tween.notifications so clients hide it from the chat list.
    def create_notification_room(user_id, domain, as_token)
      uri = URI("#{MATRIX_API_URL}/_matrix/client/v3/createRoom")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 10
      http.read_timeout = 15

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{as_token}"
      request["Content-Type"] = "application/json"
      request.body = {
        name: "Tween Notification",
        # private_chat (NOT trusted_private_chat) so the room is unencrypted and
        # the push gateway can deliver the real notification content.
        preset: "private_chat",
        is_direct: true,
        invite: [ user_id ],
        initial_state: [ { type: "m.tween.notifications", content: {} } ]
      }.to_json

      response = http.request(request)
      return nil unless response.code.to_i == 200

      JSON.parse(response.body)["room_id"]
    rescue StandardError => e
      Rails.logger.error "Failed to create notification room for #{user_id}: #{e.message}"
      nil
    end

    def get_default_room
      ENV.fetch("MATRIX_DEFAULT_ROOM", nil)
    end
  end
end
