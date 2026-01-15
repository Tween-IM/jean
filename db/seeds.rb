# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Create official mini-apps
puts "Creating official mini-apps..."

# TweenPay - Official wallet and payment mini-app
tweenpay = MiniApp.find_or_create_by!(app_id: "ma_tweenpay") do |app|
  app.name = "TweenPay"
  app.description = "Official Tween wallet and payment application"
  app.version = "1.0.0"
  app.classification = :official
  app.status = :active
  app.developer_name = "Tween IM"
  app.manifest = {
    "permissions" => [
      "wallet_balance",
      "wallet_pay",
      "wallet_history",
      "user_read",
      "storage_read",
      "storage_write",
      "messaging_send"
    ],
    "scopes" => [
      "wallet:balance",
      "wallet:pay",
      "wallet:history",
      "user:read",
      "storage:read",
      "storage:write",
      "messaging:send"
    ],
    "entry_url" => "https://miniapp.tween.im/tweenpay/",
    "redirect_uris" => [
      "https://miniapp.tween.im/tweenpay/callback"
    ],
    "webhook_url" => "https://api.tween.im/webhooks/tweenpay",
    "icon_url" => "https://cdn.tween.im/icons/tweenpay.png",
    "screenshots" => [
      "https://cdn.tween.im/screenshots/tweenpay-1.png",
      "https://cdn.tween.im/screenshots/tweenpay-2.png"
    ],
    "categories" => [ "finance", "wallet", "payments" ],
    "features" => [
      "p2p_payments",
      "balance_check",
      "transaction_history",
      "group_gifts",
      "qr_payments",
      "contact_payments"
    ]
  }
end

# TweenShop - Official marketplace mini-app
tweenshop = MiniApp.find_or_create_by!(app_id: "ma_tweenshop") do |app|
  app.name = "TweenShop"
  app.description = "Official Tween marketplace for buying and selling"
  app.version = "1.0.0"
  app.classification = :official
  app.status = :active
  app.developer_name = "Tween IM"
  app.manifest = {
    "permissions" => [
      "wallet_pay",
      "user_read",
      "storage_read",
      "storage_write",
      "messaging_send"
    ],
    "scopes" => [
      "wallet:pay",
      "user:read",
      "storage:read",
      "storage:write",
      "messaging:send"
    ],
    "entry_url" => "https://miniapp.tween.im/tweenshop/",
    "redirect_uris" => [
      "https://miniapp.tween.im/tweenshop/callback"
    ],
    "webhook_url" => "https://api.tween.im/webhooks/tweenshop",
    "icon_url" => "https://cdn.tween.im/icons/tweenshop.png",
    "categories" => [ "shopping", "marketplace", "commerce" ],
    "features" => [
      "product_listings",
      "secure_payments",
      "order_tracking",
      "seller_dashboard",
      "reviews_ratings"
    ]
  }
end

# TweenChat - Official enhanced messaging mini-app
tweenchat = MiniApp.find_or_create_by!(app_id: "ma_tweenchat") do |app|
  app.name = "TweenChat"
  app.description = "Official enhanced messaging features"
  app.version = "1.0.0"
  app.classification = :official
  app.status = :active
  app.developer_name = "Tween IM"
  app.manifest = {
    "permissions" => [
      "messaging_send",
      "messaging_read",
      "user_read",
      "storage_read",
      "storage_write"
    ],
    "scopes" => [
      "messaging:send",
      "messaging:read",
      "user:read",
      "storage:read",
      "storage:write"
    ],
    "entry_url" => "https://miniapp.tween.im/tweenchat/",
    "redirect_uris" => [
      "https://miniapp.tween.im/tweenchat/callback"
    ],
    "webhook_url" => "https://api.tween.im/webhooks/tweenchat",
    "icon_url" => "https://cdn.tween.im/icons/tweenchat.png",
    "categories" => [ "communication", "social", "messaging" ],
    "features" => [
      "rich_messaging",
      "file_sharing",
      "voice_messages",
      "message_reactions",
      "message_scheduling"
    ]
  }
end

# TweenGames - Official gaming mini-app
tweengames = MiniApp.find_or_create_by!(app_id: "ma_tweengames") do |app|
  app.name = "TweenGames"
  app.description = "Official gaming platform with wallet integration"
  app.version = "1.0.0"
  app.classification = :official
  app.status = :active
  app.developer_name = "Tween IM"
  app.manifest = {
    "permissions" => [
      "wallet_pay",
      "wallet_balance",
      "storage_read",
      "storage_write",
      "messaging_send"
    ],
    "scopes" => [
      "wallet:pay",
      "wallet:balance",
      "storage:read",
      "storage:write",
      "messaging:send"
    ],
    "entry_url" => "https://miniapp.tween.im/tweengames/",
    "redirect_uris" => [
      "https://miniapp.tween.im/tweengames/callback"
    ],
    "webhook_url" => "https://api.tween.im/webhooks/tweengames",
    "icon_url" => "https://cdn.tween.im/icons/tweengames.png",
    "categories" => [ "gaming", "entertainment", "social" ],
    "features" => [
      "multiplayer_games",
      "tournament_system",
      "prize_pools",
      "leaderboards",
      "social_features"
    ]
  }
end

puts "Official mini-apps created:"
puts "- #{tweenpay.name} (#{tweenpay.app_id})"
puts "- #{tweenshop.name} (#{tweenshop.app_id})"
puts "- #{tweenchat.name} (#{tweenchat.app_id})"
puts "- #{tweengames.name} (#{tweengames.app_id})"

# Create Doorkeeper applications for official mini-apps
puts "\nCreating OAuth applications for official mini-apps..."

official_apps = [ tweenpay, tweenshop, tweenchat, tweengames ]

official_apps.each do |mini_app|
  app = Doorkeeper::Application.find_or_create_by!(uid: mini_app.app_id) do |oauth_app|
    oauth_app.name = mini_app.name
    oauth_app.secret = SecureRandom.hex(32)
    oauth_app.redirect_uri = mini_app.manifest["redirect_uris"].join("\n")
    oauth_app.scopes = mini_app.manifest["scopes"].join(" ")
    oauth_app.confidential = true
  end

  puts "- #{app.name}: client_id=#{app.uid}, client_secret=***#{app.secret[-8..]}"
end

puts "\nOfficial mini-apps setup complete!"
puts "Run 'rails db:seed' to ensure these are created in your database."
