namespace :mini_apps do
  desc "Load official mini-apps from YAML config"
  task load_from_yaml: :environment do
    puts "Loading official mini-apps from config/mini_apps.yml..."

    synced_count = MiniAppYamlLoader.sync_mini_apps

    if synced_count > 0
      puts "✅ Successfully synced #{synced_count} mini-apps from YAML config"
    else
      puts "⚠️  No mini-apps were synced. Check the YAML file and logs."
    end
  end

  desc "Seed official mini-apps (alias for load_from_yaml)"
  task seed_official: :environment do
    Rake::Task["mini_apps:load_from_yaml"].invoke
  end

  desc "Approve all official mini-apps from YAML"
  task approve_official_from_yaml: :environment do
    puts "Approving official mini-apps from YAML config..."

    approved_count = MiniAppYamlLoader.approve_official_mini_apps

    if approved_count > 0
      puts "✅ Successfully approved #{approved_count} official mini-apps"
    else
      puts "⚠️  No mini-apps were approved. Check the YAML file and logs."
    end
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
    official_apps = MiniApp.where(classification: "official").pluck(:app_id)

    official_apps.each do |app_id|
      Rake::Task["mini_apps:approve"].invoke(app_id, "system")
      Rake::Task["mini_apps:approve"].reenable
    end

    puts "\n🎉 All official mini-apps approved!"
  end
end
