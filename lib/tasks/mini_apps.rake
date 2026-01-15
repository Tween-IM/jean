namespace :mini_apps do
  desc "Seed official mini-apps"
  task seed_official: :environment do
    puts "Seeding official mini-apps..."

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
  end

  desc "List all mini-apps"
  task list: :environment do
    puts "Mini-apps in database:"
    MiniApp.all.each do |app|
      puts "- #{app.name} (#{app.app_id}) - #{app.classification} - #{app.status}"
    end
  end

  desc "Show mini-app details"
  task :show, [ :app_id ] => :environment do |t, args|
    app = MiniApp.find_by(app_id: args[:app_id])
    if app
      puts "Mini-app: #{app.name} (#{app.app_id})"
      puts "Description: #{app.description}"
      puts "Version: #{app.version}"
      puts "Classification: #{app.classification}"
      puts "Status: #{app.status}"
      puts "Developer: #{app.developer_name}"
      puts "Manifest:"
      puts JSON.pretty_generate(app.manifest)
    else
      puts "Mini-app not found: #{args[:app_id]}"
    end
  end

  desc "Approve a mini-app (creates OAuth application)"
  task :approve, [ :app_id, :reviewer_id ] => :environment do |t, args|
    app_id = args[:app_id]
    reviewer_id = args[:reviewer_id] || "system"

    app = MiniApp.find_by(app_id: app_id)
    if app.nil?
      puts "❌ Mini-app not found: #{app_id}"
      exit 1
    end

    if app.status == "approved"
      puts "ℹ️  Mini-app #{app_id} is already approved"
      exit 0
    end

    result = MiniAppReviewService.manual_review_pass(
      miniapp: app,
      reviewer_id: reviewer_id,
      notes: "Approved via rake task"
    )

    if result[:success]
      puts "✅ Mini-app #{app_id} approved successfully"
      puts "   OAuth application created"
    else
      puts "❌ Failed to approve mini-app #{app_id}"
      exit 1
    end
  end

  desc "Approve all official mini-apps"
  task approve_official: :environment do
    official_apps = %w[ma_tweenpay ma_tweenshop ma_tweenchat ma_tweengames]

    official_apps.each do |app_id|
      Rake::Task["mini_apps:approve"].invoke(app_id, "system")
      Rake::Task["mini_apps:approve"].reenable
    end

    puts "\n🎉 All official mini-apps approved!"
  end
end
