# frozen_string_literal: true

# Demo seed data for Tween commerce + social features.
#
# Usage:
#   rails demo:seed                # Create demo content
#   rails demo:seed FORCE=1        # Re-seed even if manifest exists
#   rails demo:cleanup             # Delete all demo content using manifest
#   rails demo:cleanup DRY_RUN=1   # Preview what would be deleted
#
# The seed task writes a manifest to tmp/demo_seed_manifest.json
# so cleanup knows exactly what to destroy.

require "json"

MANIFEST_PATH = Rails.root.join("tmp/demo_seed_manifest.json").to_s

namespace :demo do
  desc "Seed demo merchants, storefronts, products, and videos"
  task seed: :environment do
    puts "🌱 Tween Demo Seed"
    puts "   Environment: #{Rails.env}"
    puts "   Manifest:    #{MANIFEST_PATH}"
    puts

    if File.exist?(MANIFEST_PATH) && ENV["FORCE"].blank?
      puts "⚠️  Manifest already exists. Run with FORCE=1 to re-seed (old content"
      puts "   will be orphaned unless you run demo:cleanup first)."
      exit 1
    end

    # -------------------------------------------------------------------------
    # Resolve dependencies
    # -------------------------------------------------------------------------
    miniapp = MiniApp.approved.or(MiniApp.active).first
    abort "❌ No approved/active MiniApp found. Create or approve one first." unless miniapp
    puts "📱 MiniApp: #{miniapp.name} (#{miniapp.app_id})"

    # Use an existing admin user or create a demo user
    demo_user = User.find_by(matrix_user_id: "@demo:tween.chat")
    if demo_user.nil?
      demo_user = User.create!(
        matrix_user_id: "@demo:tween.chat",
        matrix_username: "demo:tween.chat",
        matrix_homeserver: "tween.chat",
        platform_role: :none
      )
      puts "👤 Created demo user: #{demo_user.matrix_user_id}"
    else
      puts "👤 Using existing demo user: #{demo_user.matrix_user_id}"
    end

    manifest = {
      "seeded_at" => Time.current.iso8601,
      "environment" => Rails.env,
      "user_id" => demo_user.id,
      "user_matrix_id" => demo_user.matrix_user_id,
      "merchant_ids" => [],
      "storefront_ids" => [],
      "product_ids" => [],
      "sku_ids" => [],
      "creator_profile_ids" => [],
      "video_ids" => []
    }

    # -------------------------------------------------------------------------
    # 1. Merchant
    # -------------------------------------------------------------------------
    merchant = CommerceMerchant.find_or_initialize_by(miniapp_id: miniapp.app_id)
    if merchant.new_record?
      merchant.assign_attributes(
        display_name: "Tween Demo Shop",
        status: "active",
        owner_user_id: demo_user.matrix_user_id
      )
      merchant.save!
      puts "🏪 Created merchant: #{merchant.display_name} (#{merchant.merchant_id})"
    else
      puts "🏪 Using existing merchant: #{merchant.display_name} (#{merchant.merchant_id})"
    end
    manifest["merchant_ids"] << merchant.merchant_id

    # -------------------------------------------------------------------------
    # 2. Storefronts
    # -------------------------------------------------------------------------
    storefronts_data = [
      { display_name: "Lagos Streetwear", description: "Bold African street fashion" },
      { display_name: "Naija Tech Hub", description: "Gadgets and accessories" },
      { display_name: "Home & Comfort", description: "Everything for your living space" }
    ]

    storefronts = []
    storefronts_data.each do |sf_data|
      sf = CommerceStorefront.find_or_initialize_by(
        commerce_merchant: merchant,
        slug: sf_data[:display_name].parameterize
      )
      if sf.new_record?
        sf.assign_attributes(
          display_name: sf_data[:display_name],
          description: sf_data[:description],
          status: "published"
        )
        sf.save!
        puts "   🏠 Created storefront: #{sf.display_name}"
      else
        puts "   🏠 Using storefront: #{sf.display_name}"
      end
      storefronts << sf
      manifest["storefront_ids"] << sf.storefront_id
    end

    # -------------------------------------------------------------------------
    # 3. Products + SKUs
    # -------------------------------------------------------------------------
    products_data = [
      {
        title: "Ankara Bomber Jacket",
        description: "Hand-stitched Ankara print bomber jacket. One of a kind.",
        storefront_idx: 0,
        skus: [
          { title: "Medium / Red-Gold", price_cents: 18_500, quantity: 12 },
          { title: "Large / Blue-Green", price_cents: 19_000, quantity: 8 }
        ]
      },
      {
        title: "Aso-Oke Sneakers",
        description: "Premium sneakers with authentic Aso-Oke fabric panels.",
        storefront_idx: 0,
        skus: [
          { title: "UK 9 / Brown", price_cents: 24_000, quantity: 5 },
          { title: "UK 10 / Brown", price_cents: 24_000, quantity: 3 }
        ]
      },
      {
        title: "Wireless Earbuds Pro",
        description: "Active noise cancellation, 30-hour battery life.",
        storefront_idx: 1,
        skus: [
          { title: "Midnight Black", price_cents: 45_000, quantity: 20 },
          { title: "Cloud White", price_cents: 45_000, quantity: 15 }
        ]
      },
      {
        title: "Solar Power Bank 20,000mAh",
        description: "Charge your phone 5 times. Built-in solar panel.",
        storefront_idx: 1,
        skus: [
          { title: "Standard", price_cents: 22_000, quantity: 30 }
        ]
      },
      {
        title: "Handwoven Raffia Lamp Shade",
        description: "Sustainable raffia weave. Warm ambient lighting.",
        storefront_idx: 2,
        skus: [
          { title: "45cm diameter", price_cents: 15_500, quantity: 7 },
          { title: "60cm diameter", price_cents: 21_000, quantity: 4 }
        ]
      },
      {
        title: "Ceramic Soup Bowl Set",
        description: "Set of 4 hand-glazed ceramic bowls.",
        storefront_idx: 2,
        skus: [
          { title: "Earth Tones", price_cents: 12_000, quantity: 10 }
        ]
      }
    ]

    products_data.each do |pd|
      sf = storefronts[pd[:storefront_idx]]
      product = CommerceProduct.find_or_initialize_by(
        commerce_merchant: merchant,
        title: pd[:title]
      )
      if product.new_record?
        product.assign_attributes(
          commerce_storefront: sf,
          description: pd[:description],
          status: "active",
          media_urls: []
        )
        product.save!
        puts "   📦 Created product: #{product.title}"
      else
        puts "   📦 Using product: #{product.title}"
      end
      manifest["product_ids"] << product.product_id

      pd[:skus].each do |sku_data|
        sku = CommerceSku.find_or_initialize_by(
          commerce_product: product,
          title: sku_data[:title]
        )
        if sku.new_record?
          sku.assign_attributes(
            price_cents: sku_data[:price_cents],
            currency: "NGN",
            quantity_available: sku_data[:quantity],
            inventory_status: sku_data[:quantity] > 0 ? "in_stock" : "out_of_stock"
          )
          sku.save!
        end
        manifest["sku_ids"] << sku.sku_id
      end
    end

    # -------------------------------------------------------------------------
    # 4. Creator Profile
    # -------------------------------------------------------------------------
    creator = SocialCreatorProfile.find_or_initialize_by(user_id: demo_user.matrix_user_id)
    if creator.new_record?
      creator.assign_attributes(
        handle: "tween_demo",
        display_name: "Tween Demo Creator",
        bio: "Official demo account for Tween social commerce.",
        avatar_url: "https://api.dicebear.com/7.x/avataaars/svg?seed=tween",
        verified: true
      )
      creator.save!
      puts "🎬 Created creator: #{creator.display_name} (@#{creator.handle})"
    else
      puts "🎬 Using creator: #{creator.display_name} (@#{creator.handle})"
    end
    manifest["creator_profile_ids"] << creator.user_id

    # -------------------------------------------------------------------------
    # 5. Videos (public sample videos — all open source / CC)
    # -------------------------------------------------------------------------
    sample_videos = [
      {
        caption: "Unboxing the Solar Power Bank — 5 full charges on one unit! ⚡ #tweenfinds #tech",
        playback_url: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/WeAreGoingOnBullrun.mp4",
        thumbnail_url: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/WeAreGoingOnBullrun.jpg",
        commerce_refs: []
      },
      {
        caption: "Morning routine in my Ankara jacket. Lagos heat no match 🔥 #streetwear #madeinnigeria",
        playback_url: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
        thumbnail_url: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/BigBuckBunny.jpg",
        commerce_refs: []
      },
      {
        caption: "These wireless earbuds are INSANE for the price. Noise cancelling test 👇 #review #gadgets",
        playback_url: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4",
        thumbnail_url: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ElephantsDream.jpg",
        commerce_refs: []
      },
      {
        caption: "How I style the Raffia lamp in my living room. Warm vibes only 💡 #homedecor #sustainable",
        playback_url: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4",
        thumbnail_url: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/TearsOfSteel.jpg",
        commerce_refs: []
      },
      {
        caption: "Aso-Oke sneakers — from loom to sole. Full production story 🧵 #sneakers #craft",
        playback_url: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4",
        thumbnail_url: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/Sintel.jpg",
        commerce_refs: []
      }
    ]

    # Link some videos to products for commerce integration demo
    product_ids = manifest["product_ids"]
    sample_videos[0][:commerce_refs] = [product_ids[3]] # Solar Power Bank
    sample_videos[1][:commerce_refs] = [product_ids[0]] # Ankara Jacket
    sample_videos[2][:commerce_refs] = [product_ids[2]] # Earbuds
    sample_videos[3][:commerce_refs] = [product_ids[4]] # Raffia Lamp
    sample_videos[4][:commerce_refs] = [product_ids[1]] # Aso-Oke Sneakers

    sample_videos.each_with_index do |vd, idx|
      video = SocialVideo.find_or_initialize_by(
        creator_user_id: demo_user.matrix_user_id,
        playback_url: vd[:playback_url]
      )
      if video.new_record?
        video.assign_attributes(
          caption: vd[:caption],
          thumbnail_url: vd[:thumbnail_url],
          commerce_refs: vd[:commerce_refs],
          visibility: "public",
          status: "published",
          moderation_status: "approved",
          published_at: Time.current - (idx * 2).hours,
          view_count: rand(1200..8500),
          like_count: rand(200..1200),
          comment_count: rand(15..80),
          share_count: rand(5..40),
          duration_seconds: rand(15..45),
          width: 1080,
          height: 1920
        )
        video.save!
        puts "   🎥 Created video: #{video.caption.to_s[0..50]}..."
      else
        puts "   🎥 Using video: #{video.caption.to_s[0..50]}..."
      end
      manifest["video_ids"] << video.video_id
    end

    # -------------------------------------------------------------------------
    # Write manifest
    # -------------------------------------------------------------------------
    File.write(MANIFEST_PATH, JSON.pretty_generate(manifest))

    puts
    puts "✅ Demo seed complete!"
    puts "   Merchants:    #{manifest['merchant_ids'].count}"
    puts "   Storefronts:  #{manifest['storefront_ids'].count}"
    puts "   Products:     #{manifest['product_ids'].count}"
    puts "   SKUs:         #{manifest['sku_ids'].count}"
    puts "   Creators:     #{manifest['creator_profile_ids'].count}"
    puts "   Videos:       #{manifest['video_ids'].count}"
    puts
    puts "   Cleanup: rails demo:cleanup"
  end

  desc "Remove all demo content using the manifest"
  task cleanup: :environment do
    unless File.exist?(MANIFEST_PATH)
      abort "❌ Manifest not found at #{MANIFEST_PATH}. Run 'rails demo:seed' first."
    end

    manifest = JSON.parse(File.read(MANIFEST_PATH))
    dry_run = ENV["DRY_RUN"].present?

    puts "🧹 Tween Demo Cleanup"
    puts "   Environment: #{Rails.env}"
    puts "   Seeded at:   #{manifest['seeded_at']}"
    puts "   Dry run:     #{dry_run ? 'YES (no deletes)' : 'NO'}"
    puts

    # -------------------------------------------------------------------------
    # Destroy in reverse dependency order
    # -------------------------------------------------------------------------

    # Videos
    manifest["video_ids"].each do |vid|
      video = SocialVideo.find_by(video_id: vid)
      if video
        puts "   🗑️  Video: #{video.caption.to_s[0..40]}..."
        video.destroy! unless dry_run
      end
    end

    # Creator profiles
    manifest["creator_profile_ids"].each do |uid|
      profile = SocialCreatorProfile.find_by(user_id: uid)
      if profile
        puts "   🗑️  Creator: #{profile.display_name}"
        profile.destroy! unless dry_run
      end
    end

    # SKUs
    manifest["sku_ids"].each do |sid|
      sku = CommerceSku.find_by(sku_id: sid)
      if sku
        puts "   🗑️  SKU: #{sku.title}"
        sku.destroy! unless dry_run
      end
    end

    # Products
    manifest["product_ids"].each do |pid|
      product = CommerceProduct.find_by(product_id: pid)
      if product
        puts "   🗑️  Product: #{product.title}"
        product.destroy! unless dry_run
      end
    end

    # Storefronts
    manifest["storefront_ids"].each do |stid|
      sf = CommerceStorefront.find_by(storefront_id: stid)
      if sf
        puts "   🗑️  Storefront: #{sf.display_name}"
        sf.destroy! unless dry_run
      end
    end

    # Merchants (has dependent: :destroy on products/storefronts but we already cleaned those)
    manifest["merchant_ids"].each do |mid|
      merchant = CommerceMerchant.find_by(merchant_id: mid)
      if merchant
        puts "   🗑️  Merchant: #{merchant.display_name}"
        merchant.destroy! unless dry_run
      end
    end

    unless dry_run
      File.delete(MANIFEST_PATH) if File.exist?(MANIFEST_PATH)
    end

    puts
    puts dry_run ? "🏁 Dry run complete. No records deleted." : "✅ Cleanup complete."
    puts "   Manifest #{dry_run ? 'kept' : 'removed'}: #{MANIFEST_PATH}"
  end
end
