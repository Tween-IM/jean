# frozen_string_literal: true

# Social notification seeds for @mona:tween.im
# All notifications target mona as the recipient.
# Run with: rails db:seed  (called from db/seeds.rb)

puts "\n📬 Seeding notifications for @mona:tween.im..."

mona_id = "@mona:tween.im"
seeded = 0

# Ensure mona has a comment from another user for reply/mention notifications
post = SocialPost.find_by(post_id: "post_iju1sjv5yndr") || SocialPost.where(creator_user_id: mona_id).first

comment = SocialComment.find_or_create_by!(id: 90_001) do |c|
  c.social_post = post
  c.author_user_id = "@emeka:tween.im"
  c.body = "This is stunning! Where was this taken?"
  c.created_at = 16.hours.ago
end

# ---------------------------------------------------------------------------
# Like notifications (6 — 4 unread, 2 read)
# ---------------------------------------------------------------------------

[
  { actor: "@chioma:tween.im",   post_id: "post_iju1sjv5yndr", caption: "Quite a picture",       ago: 30.minutes,    read: false },
  { actor: "@emeka:tween.im",    post_id: "post_cowg8dfymcuq", caption: "Some stuffs init",       ago: 45.minutes,    read: false },
  { actor: "@fatima:tween.im",   post_id: "post_gav16f9egird", caption: "oi oi",                  ago: 1.hour,        read: false },
  { actor: "@amara:tween.im",    post_id: "post_9xfecvmu5dcn", caption: "Ty Lopez",               ago: 90.minutes,    read: false },
  { actor: "@tunde:tween.im",    post_id: "post_dcruahnjiot1", caption: "Awesomely beautiful",    ago: 3.hours,       read: true  },
  { actor: "@chioma:tween.im",   post_id: "post_tx5n0pkb4eub", caption: "Awesomeness on my mind", ago: 1.day,         read: true  },
].each do |n|
  attrs = {
    user_id: mona_id, actor_id: n[:actor], notification_type: :like, source: :social,
    target_type: "post", target_id: n[:post_id],
    title: "New like",
    body: "#{SocialCreatorProfile.find_by(user_id: n[:actor])&.display_name || n[:actor]} liked your post",
    created_at: n[:ago].ago,
    metadata: { post_caption: n[:caption] }
  }
  attrs[:read_at] = (n[:ago].ago + 2.minutes) if n[:read]
  Notification.find_or_create_by!(notification_type: :like, user_id: mona_id, actor_id: n[:actor], target_id: n[:post_id]) { |r| r.assign_attributes(attrs) }
  seeded += 1
end

# ---------------------------------------------------------------------------
# Comment notifications (3 — 2 unread, 1 read)
# ---------------------------------------------------------------------------

[
  { actor: "@fatima:tween.im", post_id: "post_iju1sjv5yndr", caption: "Quite a picture",     body: "Love the composition! What camera?",     ago: 2.hours,   read: false },
  { actor: "@tunde:tween.im",  post_id: "post_1mapdg8qa0qi", caption: "yo😎",                 body: "Bro this is fire 🔥",                   ago: 5.hours,   read: false },
  { actor: "@amara:tween.im",  post_id: "post_dcruahnjiot1", caption: "Awesomely beautiful",  body: "So beautiful, where is this?",          ago: 2.days,    read: true  },
].each do |n|
  attrs = {
    user_id: mona_id, actor_id: n[:actor], notification_type: :comment, source: :social,
    target_type: "post", target_id: n[:post_id],
    title: "New comment",
    body: "#{SocialCreatorProfile.find_by(user_id: n[:actor])&.display_name || n[:actor]} commented on your post",
    created_at: n[:ago].ago,
    metadata: { comment_body: n[:body], post_caption: n[:caption] }
  }
  attrs[:read_at] = (n[:ago].ago + 5.minutes) if n[:read]
  Notification.find_or_create_by!(notification_type: :comment, user_id: mona_id, actor_id: n[:actor], target_id: n[:post_id]) { |r| r.assign_attributes(attrs) }
  seeded += 1
end

# ---------------------------------------------------------------------------
# Mention / reply notification (1)
# ---------------------------------------------------------------------------

unless Notification.exists?(notification_type: :mention, user_id: mona_id)
  Notification.create!(
    user_id: mona_id,
    actor_id: "@fatima:tween.im",
    notification_type: :mention,
    source: :social,
    target_type: "comment",
    target_id: comment.id.to_s,
    title: "New reply",
    body: "Fatima Cooks replied to your comment",
    created_at: 3.hours.ago,
    metadata: { comment_id: comment.id, comment_body: "Right?! It's at Tarkwa Bay. You'd love it!", post_id: post.post_id }
  )
  seeded += 1
end

# ---------------------------------------------------------------------------
# Follow notifications (3 — all unread)
# ---------------------------------------------------------------------------

[
  { actor: "@chioma:tween.im", ago: 15.minutes  },
  { actor: "@emeka:tween.im",  ago: 1.hour      },
  { actor: "@amara:tween.im",  ago: 4.hours     },
].each do |n|
  unless Notification.exists?(notification_type: :follow, user_id: mona_id, actor_id: n[:actor])
    follower = SocialCreatorProfile.find_by(user_id: n[:actor])
    Notification.create!(
      user_id: mona_id,
      actor_id: n[:actor],
      notification_type: :follow,
      source: :social,
      target_type: "creator",
      target_id: mona_id,
      title: "New follower",
      body: "#{follower&.display_name || n[:actor]} started following you",
      created_at: n[:ago].ago,
      metadata: { follower_handle: follower&.handle, follower_display_name: follower&.display_name }
    )
    seeded += 1
  end
end

# ---------------------------------------------------------------------------
# System notification (1)
# ---------------------------------------------------------------------------

unless Notification.exists?(notification_type: :system, user_id: mona_id)
  Notification.create!(
    user_id: mona_id,
    notification_type: :system,
    source: :system,
    title: "Welcome to Tween Social, Monalito!",
    body: "Your profile is live. Create your first post, follow creators, and start building your audience.",
    created_at: 14.days.ago,
    read_at: 14.days.ago,
    metadata: { onboarding: true, first_login: true }
  )
  seeded += 1
end

# ---------------------------------------------------------------------------
# Payment notification (1 — read)
# ---------------------------------------------------------------------------

unless Notification.exists?(notification_type: :payment, user_id: mona_id, body: "You received ₦25,000 from a Tween Shop sale")
  Notification.create!(
    user_id: mona_id,
    notification_type: :payment,
    source: :tweenpay,
    target_type: "payment",
    target_id: "pay_shop_sale_mona_seed",
    title: "Shop sale",
    body: "You received ₦25,000 from a Tween Shop sale",
    created_at: 6.hours.ago,
    read_at: 6.hours.ago,
    metadata: { amount: 25_000, currency: "NGN", order_id: "ord_seed_shop_01" }
  )
  seeded += 1
end

puts "   ✅ #{seeded} notifications seeded for @mona:tween.im"
