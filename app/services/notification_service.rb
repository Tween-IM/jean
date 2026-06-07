# frozen_string_literal: true

# NotificationService
#
# Central service for creating notifications. Any controller or external
# service (tweenpay, commerce, etc.) can call these class methods to
# generate user-facing notifications.
#
# Social controllers call the typed helpers (create_like_notification,
# create_comment_notification, create_follow_notification).
#
# External services call the generic create_from_external entry point.
#
class NotificationService
  class << self
    # -------------------------------------------------------------------------
    # Social notifications
    # -------------------------------------------------------------------------

    def create_like_notification(post:, actor_user_id:, actor_display_name: nil)
      return if post.creator_user_id == actor_user_id

      actor = SocialCreatorProfile.find_by(user_id: actor_user_id)

      Notification.create!(
        user_id: post.creator_user_id,
        actor_id: actor_user_id,
        notification_type: :like,
        source: :social,
        target_type: "post",
        target_id: post.post_id,
        title: "New like",
        body: "#{actor_display_name || actor&.display_name || "Someone"} liked your post",
        metadata: {
          post_caption: post.caption&.truncate(100),
          post_thumbnail_url: post.thumbnail_url
        }
      )
    end

    def create_comment_notification(comment:, actor_user_id:, actor_display_name: nil)
      post = comment.social_post
      actor = SocialCreatorProfile.find_by(user_id: actor_user_id)
      name = actor_display_name || actor&.display_name || "Someone"

      # Notify post owner (unless actor is the owner)
      if post.creator_user_id != actor_user_id
        Notification.create!(
          user_id: post.creator_user_id,
          actor_id: actor_user_id,
          notification_type: :comment,
          source: :social,
          target_type: "post",
          target_id: post.post_id,
          title: "New comment",
          body: "#{name} commented on your post",
          metadata: {
            comment_id: comment.id,
            comment_body: comment.body&.truncate(100),
            post_caption: post.caption&.truncate(100)
          }
        )
      end

      # Notify parent comment author (if this is a reply)
      if comment.parent_comment_id.present?
        parent = SocialComment.find_by(id: comment.parent_comment_id)
        if parent && parent.author_user_id != actor_user_id && parent.author_user_id != post.creator_user_id
          Notification.create!(
            user_id: parent.author_user_id,
            actor_id: actor_user_id,
            notification_type: :mention,
            source: :social,
            target_type: "comment",
            target_id: comment.id.to_s,
            title: "New reply",
            body: "#{name} replied to your comment",
            metadata: {
              comment_id: comment.id,
              comment_body: comment.body&.truncate(100),
              post_id: post.post_id
            }
          )
        end
      end
    end

    def create_follow_notification(creator:, follower_user_id:, follower_display_name: nil)
      return if creator.user_id == follower_user_id

      follower = SocialCreatorProfile.find_by(user_id: follower_user_id)
      name = follower_display_name || follower&.display_name || follower&.handle || "Someone"

      Notification.create!(
        user_id: creator.user_id,
        actor_id: follower_user_id,
        notification_type: :follow,
        source: :social,
        target_type: "creator",
        target_id: creator.user_id,
        title: "New follower",
        body: "#{name} started following you",
        metadata: {
          follower_handle: follower&.handle,
          follower_display_name: follower&.display_name
        }
      )
    end

    # -------------------------------------------------------------------------
    # Generic extensible entry point
    # -------------------------------------------------------------------------
    #
    # tweenpay, commerce, or any external service calls this to create
    # a notification. No schema changes needed — the source enum already
    # supports :tweenpay, :commerce, :system, etc.
    #
    # Example (tweenpay payment received):
    #   NotificationService.create_from_external(
    #     source: :tweenpay,
    #     user_id: recipient.matrix_user_id,
    #     notification_type: :payment,
    #     title: "Payment received",
    #     body: "You received ₦5,000 from Alice",
    #     target_type: "payment",
    #     target_id: payment_id,
    #     metadata: { amount: 5000, currency: "NGN" }
    #   )
    #
    def create_from_external(
      source:,
      user_id:,
      notification_type:,
      title:,
      body:,
      target_type: nil,
      target_id: nil,
      metadata: {},
      actor_id: nil
    )
      Notification.create!(
        user_id: user_id,
        actor_id: actor_id,
        notification_type: notification_type,
        source: source,
        target_type: target_type,
        target_id: target_id,
        title: title,
        body: body,
        metadata: metadata
      )
    end
  end
end
