# frozen_string_literal: true

# Social notification seeds for @fantabulous:tween.im
# Creates the creator profile + sample posts + notifications.
# Run with: rails db:seed  (called from db/seeds.rb)

puts "\n📬 Seeding notifications for @fantabulous:tween.im..."

fan_id = "@fantabulous:tween.im"
seeded = 0

# ---------------------------------------------------------------------------
# 1. Create creator profile
# ---------------------------------------------------------------------------

fan = SocialCreatorProfile.find_or_create_by!(user_id: fan_id) do |p|
  p.handle = "fantabulous"
  p.display_name = "Fantabulous"
  p.bio = "Living my best life ✨ | Fashion, travel, vibes"
end

# ---------------------------------------------------------------------------
# 2. Create sample posts
# ---------------------------------------------------------------------------

p1 = SocialPost.find_or_create_by!(post_id: "post_fan_01") do |p|
  p.creator_user_id = fan_id
  p.caption = "Sunday brunch vibes 🥂"
  p.content_type = "photo"
  p.status = "published"
  p.moderation_status = "approved"
  p.visibility = "public"
  p.published_at = 3.days.ago
end

p2 = SocialPost.find_or_create_by!(post_id: "post_fan_02") do |p|
  p.creator_user_id = fan_id
  p.caption = "New fit, who dis? 💅"
  p.content_type = "photo"
  p.status = "published"
  p.moderation_status = "approved"
  p.visibility = "public"
  p.published_at = 1.day.ago
end

p3 = SocialPost.find_or_create_by!(post_id: "post_fan_03") do |p|
  p.creator_user_id = fan_id
  p.caption = "Lagos nights hit different 🌃"
  p.content_type = "video"
  p.status = "published"
  p.moderation_status = "approved"
  p.visibility = "public"
  p.published_at = 6.hours.ago
end

# ---------------------------------------------------------------------------
# 3. Create a comment (for reply/mention notifications)
# ---------------------------------------------------------------------------

fan_comment = SocialComment.find_or_create_by!(id: 90_003) do |c|
  c.social_post = p2
  c.author_user_id = "@chioma:tween.im"
  c.body = "This fit is everything! Where'd you get the jacket?"
  c.created_at = 12.hours.ago
end

# ---------------------------------------------------------------------------
# 4. Like notifications (5)
# ---------------------------------------------------------------------------

[
  { actor: "@chioma:tween.im", post: p1, ago: 20.minutes,  read: false },
  { actor: "@emeka:tween.im",  post: p2, ago: 1.hour,     read: false },
  { actor: "@fatima:tween.im", post: p3, ago: 2.hours,    read: false },
  { actor: "@amara:tween.im",  post: p1, ago: 5.hours,    read: false },
  { actor: "@tunde:tween.im",  post: p2, ago: 1.day,      read: true  },
].each do |n|
  actor_name = SocialCreatorProfile.find_by(user_id: n[:actor])&.display_name || n[:actor]
  attrs = {
    user_id: fan_id, actor_id: n[:actor], notification_type: :like, source: :social,
    target_type: "post", target_id: n[:post].post_id,
    title: "New like",
    body: "#{actor_name} liked your post",
    created_at: n[:ago].ago,
    metadata: { post_caption: n[:post].caption }
  }
  attrs[:read_at] = (n[:ago].ago + 3.minutes) if n[:read]
  Notification.find_or_create_by!(notification_type: :like, user_id: fan_id, actor_id: n[:actor], target_id: n[:post].post_id) { |r| r.assign_attributes(attrs) }
  seeded += 1
end

# ---------------------------------------------------------------------------
# 5. Comment notifications (2)
# ---------------------------------------------------------------------------

[
  { actor: "@fatima:tween.im", post: p3, body: "Girl you're glowing! 😍",             ago: 1.hour,   read: false },
  { actor: "@emeka:tween.im",  post: p1, body: "Save me a plate! Looks delicious",   ago: 2.days,   read: true  },
].each do |n|
  actor_name = SocialCreatorProfile.find_by(user_id: n[:actor])&.display_name || n[:actor]
  attrs = {
    user_id: fan_id, actor_id: n[:actor], notification_type: :comment, source: :social,
    target_type: "post", target_id: n[:post].post_id,
    title: "New comment",
    body: "#{actor_name} commented on your post",
    created_at: n[:ago].ago,
    metadata: { comment_body: n[:body], post_caption: n[:post].caption }
  }
  attrs[:read_at] = (n[:ago].ago + 10.minutes) if n[:read]
  Notification.find_or_create_by!(notification_type: :comment, user_id: fan_id, actor_id: n[:actor], target_id: n[:post].post_id) { |r| r.assign_attributes(attrs) }
  seeded += 1
end

# ---------------------------------------------------------------------------
# 6. Mention / reply notification (1)
# ---------------------------------------------------------------------------

unless Notification.exists?(notification_type: :mention, user_id: fan_id)
  Notification.create!(
    user_id: fan_id,
    actor_id: "@chioma:tween.im",
    notification_type: :mention,
    source: :social,
    target_type: "comment",
    target_id: fan_comment.id.to_s,
    title: "New reply",
    body: "Chioma replied to your comment",
    created_at: 9.hours.ago,
    metadata: { comment_id: fan_comment.id, comment_body: "Got it from Zara last week! They have a sale rn 👀", post_id: p2.post_id }
  )
  seeded += 1
end

# ---------------------------------------------------------------------------
# 7. Follow notifications (4)
# ---------------------------------------------------------------------------

[
  { actor: "@mona:tween.im",   ago: 10.minutes },
  { actor: "@chioma:tween.im", ago: 30.minutes },
  { actor: "@tunde:tween.im",  ago: 2.hours    },
  { actor: "@amara:tween.im",  ago: 6.hours    },
].each do |n|
  unless Notification.exists?(notification_type: :follow, user_id: fan_id, actor_id: n[:actor])
    follower = SocialCreatorProfile.find_by(user_id: n[:actor])
    Notification.create!(
      user_id: fan_id,
      actor_id: n[:actor],
      notification_type: :follow,
      source: :social,
      target_type: "creator",
      target_id: fan_id,
      title: "New follower",
      body: "#{follower&.display_name || n[:actor]} started following you",
      created_at: n[:ago].ago,
      metadata: { follower_handle: follower&.handle, follower_display_name: follower&.display_name }
    )
    seeded += 1
  end
end

# ---------------------------------------------------------------------------
# 8. System notification (1)
# ---------------------------------------------------------------------------

unless Notification.exists?(notification_type: :system, user_id: fan_id)
  Notification.create!(
    user_id: fan_id,
    notification_type: :system,
    source: :system,
    title: "Welcome to Tween Social, Fantabulous!",
    body: "Your world, your rules. Start posting, connect with creators, and grow your tribe.",
    created_at: 10.days.ago,
    read_at: 10.days.ago,
    metadata: { onboarding: true }
  )
  seeded += 1
end

puts "   ✅ #{seeded} notifications seeded for @fantabulous:tween.im"
