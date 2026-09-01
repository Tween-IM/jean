# frozen_string_literal: true

# Central service for creating notifications. Any controller or external
# service (tweenpay, commerce, etc.) can call these class methods to
# generate user-facing notifications.
#
# All notifications route through NotificationDispatcher, which handles
# in-app records, FCM push, and email based on user preferences.
#
class NotificationService
  class << self
    # -------------------------------------------------------------------------
    # Social notifications
    # -------------------------------------------------------------------------

    def create_like_notification(post:, actor_user_id:, actor_display_name: nil)
      return if post.creator_user_id == actor_user_id

      actor = SocialCreatorProfile.find_by(user_id: actor_user_id)

      NotificationDispatcher.notify(
        user_id: post.creator_user_id,
        source: :social,
        notification_type: :like,
        title: "New like",
        body: "#{actor_display_name || actor&.display_name || "Someone"} liked your post",
        target_type: "post",
        target_id: post.post_id,
        actor_id: actor_user_id,
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
        NotificationDispatcher.notify(
          user_id: post.creator_user_id,
          source: :social,
          notification_type: :comment,
          title: "New comment",
          body: "#{name} commented on your post",
          target_type: "post",
          target_id: post.post_id,
          actor_id: actor_user_id,
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
          NotificationDispatcher.notify(
            user_id: parent.author_user_id,
            source: :social,
            notification_type: :mention,
            title: "New reply",
            body: "#{name} replied to your comment",
            target_type: "comment",
            target_id: comment.id.to_s,
            actor_id: actor_user_id,
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

      NotificationDispatcher.notify(
        user_id: creator.user_id,
        source: :social,
        notification_type: :follow,
        title: "New follower",
        body: "#{name} started following you",
        target_type: "creator",
        target_id: creator.user_id,
        actor_id: follower_user_id,
        metadata: {
          follower_handle: follower&.handle,
          follower_display_name: follower&.display_name
        }
      )
    end

    # -------------------------------------------------------------------------
    # Generic extensible entry point
    # -------------------------------------------------------------------------

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
      NotificationDispatcher.notify(
        user_id: user_id,
        source: source,
        notification_type: notification_type,
        title: title,
        body: body,
        target_type: target_type,
        target_id: target_id,
        actor_id: actor_id,
        metadata: metadata
      )
    end
  end
end
