# frozen_string_literal: true

# Social notification seeds — idempotent, skips if data already exists.
# Run with: rails db:seed

puts "\n📬 Seeding social notifications..."

# ---------------------------------------------------------------------------
# 1. Ensure creator profiles exist (actors)
# ---------------------------------------------------------------------------

unless SocialCreatorProfile.exists?(handle: "chioma")
  SocialCreatorProfile.create!(
    user_id: "@chioma:tween.im",
    handle: "chioma",
    display_name: "Chioma",
    bio: "Fashion & lifestyle creator"
  )
end

unless SocialCreatorProfile.exists?(handle: "emeka")
  SocialCreatorProfile.create!(
    user_id: "@emeka:tween.im",
    handle: "emeka",
    display_name: "Emeka Styles",
    bio: "Photographer & traveler"
  )
end

unless SocialCreatorProfile.exists?(handle: "fatima")
  SocialCreatorProfile.create!(
    user_id: "@fatima:tween.im",
    handle: "fatima",
    display_name: "Fatima Cooks",
    bio: "Food blogger | Recipe developer"
  )
end

unless SocialCreatorProfile.exists?(handle: "tunde")
  SocialCreatorProfile.create!(
    user_id: "@tunde:tween.im",
    handle: "tunde",
    display_name: "Tunde Tech",
    bio: "Tech reviews & unboxings"
  )
end

unless SocialCreatorProfile.exists?(handle: "amara")
  SocialCreatorProfile.create!(
    user_id: "@amara:tween.im",
    handle: "amara",
    display_name: "Amara Beauty",
    bio: "Skincare & beauty tips"
  )
end

puts "   ✅ Creator profiles ready"

# ---------------------------------------------------------------------------
# 2. Ensure sample posts exist (targets for like/comment notifications)
# ---------------------------------------------------------------------------

unless SocialPost.exists?(post_id: "seed-post-01")
  SocialPost.create!(
    post_id: "seed-post-01",
    creator_user_id: "@chioma:tween.im",
    caption: "New Ankara collection dropping this weekend! 🔥",
    content_type: "photo",
    status: "published",
    moderation_status: "approved",
    visibility: "public",
    published_at: 2.days.ago
  )
end

unless SocialPost.exists?(post_id: "seed-post-02")
  SocialPost.create!(
    post_id: "seed-post-02",
    creator_user_id: "@emeka:tween.im",
    caption: "Golden hour at Lagos beach 🌅",
    content_type: "photo",
    status: "published",
    moderation_status: "approved",
    visibility: "public",
    published_at: 3.days.ago
  )
end

unless SocialPost.exists?(post_id: "seed-post-03")
  SocialPost.create!(
    post_id: "seed-post-03",
    creator_user_id: "@fatima:tween.im",
    caption: "Jollof rice recipe that will change your life! Full video on my page 🍛",
    content_type: "video",
    status: "published",
    moderation_status: "approved",
    visibility: "public",
    published_at: 5.days.ago
  )
end

puts "   ✅ Sample posts ready"

# ---------------------------------------------------------------------------
# 3. Ensure a sample comment exists (for reply/mention notifications)
# ---------------------------------------------------------------------------

unless SocialComment.exists?(id: 10_001)
  SocialComment.create!(
    id: 10_001,
    social_post_id: SocialPost.find_by!(post_id: "seed-post-01").id,
    author_user_id: "@fatima:tween.im",
    body: "Can't wait to see this! What colors are you doing?",
    created_at: 1.day.ago
  )
end

puts "   ✅ Sample comment ready"

# ---------------------------------------------------------------------------
# 4. Seed notifications (idempotent via Notification.exists?)
# ---------------------------------------------------------------------------

seeded = 0

# --- Like notifications ---

unless Notification.exists?(notification_type: :like, user_id: "@chioma:tween.im", actor_id: "@emeka:tween.im")
  Notification.create!(
    user_id: "@chioma:tween.im",
    actor_id: "@emeka:tween.im",
    notification_type: :like,
    source: :social,
    target_type: "post",
    target_id: "seed-post-01",
    title: "New like",
    body: "Emeka Styles liked your post",
    created_at: 2.hours.ago,
    metadata: { post_caption: "New Ankara collection dropping this weekend!", post_thumbnail_url: nil }
  )
  seeded += 1
end

unless Notification.exists?(notification_type: :like, user_id: "@chioma:tween.im", actor_id: "@fatima:tween.im")
  Notification.create!(
    user_id: "@chioma:tween.im",
    actor_id: "@fatima:tween.im",
    notification_type: :like,
    source: :social,
    target_type: "post",
    target_id: "seed-post-01",
    title: "New like",
    body: "Fatima Cooks liked your post",
    created_at: 4.hours.ago,
    metadata: { post_caption: "New Ankara collection dropping this weekend!", post_thumbnail_url: nil }
  )
  seeded += 1
end

unless Notification.exists?(notification_type: :like, user_id: "@emeka:tween.im", actor_id: "@chioma:tween.im")
  Notification.create!(
    user_id: "@emeka:tween.im",
    actor_id: "@chioma:tween.im",
    notification_type: :like,
    source: :social,
    target_type: "post",
    target_id: "seed-post-02",
    title: "New like",
    body: "Chioma liked your post",
    created_at: 6.hours.ago,
    read_at: 5.hours.ago,
    metadata: { post_caption: "Golden hour at Lagos beach", post_thumbnail_url: nil }
  )
  seeded += 1
end

# --- Comment notifications ---

unless Notification.exists?(notification_type: :comment, user_id: "@chioma:tween.im", actor_id: "@fatima:tween.im")
  Notification.create!(
    user_id: "@chioma:tween.im",
    actor_id: "@fatima:tween.im",
    notification_type: :comment,
    source: :social,
    target_type: "post",
    target_id: "seed-post-01",
    title: "New comment",
    body: "Fatima Cooks commented on your post",
    created_at: 1.day.ago,
    metadata: { comment_id: 10_001, comment_body: "Can't wait to see this!", post_caption: "New Ankara collection" }
  )
  seeded += 1
end

unless Notification.exists?(notification_type: :comment, user_id: "@emeka:tween.im", actor_id: "@tunde:tween.im")
  Notification.create!(
    user_id: "@emeka:tween.im",
    actor_id: "@tunde:tween.im",
    notification_type: :comment,
    source: :social,
    target_type: "post",
    target_id: "seed-post-02",
    title: "New comment",
    body: "Tunde Tech commented on your post",
    created_at: 18.hours.ago,
    metadata: { comment_id: nil, comment_body: "Nice shot! What camera?", post_caption: "Golden hour at Lagos beach" }
  )
  seeded += 1
end

# --- Mention / reply notification ---

unless Notification.exists?(notification_type: :mention, user_id: "@fatima:tween.im", actor_id: "@chioma:tween.im")
  Notification.create!(
    user_id: "@fatima:tween.im",
    actor_id: "@chioma:tween.im",
    notification_type: :mention,
    source: :social,
    target_type: "comment",
    target_id: 10_001.to_s,
    title: "New reply",
    body: "Chioma replied to your comment",
    created_at: 12.hours.ago,
    metadata: { comment_id: 10_001, comment_body: "Royal blue, emerald green, and burnt orange!", post_id: "seed-post-01" }
  )
  seeded += 1
end

# --- Follow notifications ---

unless Notification.exists?(notification_type: :follow, user_id: "@chioma:tween.im", actor_id: "@amara:tween.im")
  Notification.create!(
    user_id: "@chioma:tween.im",
    actor_id: "@amara:tween.im",
    notification_type: :follow,
    source: :social,
    target_type: "creator",
    target_id: "@chioma:tween.im",
    title: "New follower",
    body: "Amara Beauty started following you",
    created_at: 3.hours.ago,
    metadata: { follower_handle: "amara", follower_display_name: "Amara Beauty" }
  )
  seeded += 1
end

unless Notification.exists?(notification_type: :follow, user_id: "@fatima:tween.im", actor_id: "@tunde:tween.im")
  Notification.create!(
    user_id: "@fatima:tween.im",
    actor_id: "@tunde:tween.im",
    notification_type: :follow,
    source: :social,
    target_type: "creator",
    target_id: "@fatima:tween.im",
    title: "New follower",
    body: "Tunde Tech started following you",
    created_at: 1.day.ago,
    read_at: 23.hours.ago,
    metadata: { follower_handle: "tunde", follower_display_name: "Tunde Tech" }
  )
  seeded += 1
end

unless Notification.exists?(notification_type: :follow, user_id: "@emeka:tween.im", actor_id: "@chioma:tween.im")
  Notification.create!(
    user_id: "@emeka:tween.im",
    actor_id: "@chioma:tween.im",
    notification_type: :follow,
    source: :social,
    target_type: "creator",
    target_id: "@emeka:tween.im",
    title: "New follower",
    body: "Chioma started following you",
    created_at: 2.days.ago,
    read_at: 1.day.ago,
    metadata: { follower_handle: "chioma", follower_display_name: "Chioma" }
  )
  seeded += 1
end

# --- System welcome notification ---

unless Notification.exists?(notification_type: :system, user_id: "@chioma:tween.im")
  Notification.create!(
    user_id: "@chioma:tween.im",
    notification_type: :system,
    source: :system,
    title: "Welcome to Tween Social",
    body: "Start creating, connect with others, and share your world. Your first followers are waiting!",
    created_at: 7.days.ago,
    read_at: 7.days.ago,
    metadata: { onboarding: true }
  )
  seeded += 1
end

# --- Payment notification (for variety) ---

unless Notification.exists?(notification_type: :payment, user_id: "@chioma:tween.im")
  Notification.create!(
    user_id: "@chioma:tween.im",
    notification_type: :payment,
    source: :tweenpay,
    target_type: "payment",
    target_id: "pay_wallet_topup_seed",
    title: "Wallet topped up",
    body: "You added ₦10,000 to your Tween wallet",
    created_at: 8.hours.ago,
    read_at: 8.hours.ago,
    metadata: { amount: 10_000, currency: "NGN" }
  )
  seeded += 1
end

puts "   ✅ #{seeded} notifications seeded (skipped #{11 - seeded} existing)"
puts "\n🎉 Social notification seeding complete!"
