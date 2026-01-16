class MiniAppYamlLoader
  MINI_APPS_CONFIG_PATH = Rails.root.join("config", "mini_apps.yml")

  def self.load_from_yaml
    unless File.exist?(MINI_APPS_CONFIG_PATH)
      Rails.logger.error "Mini-apps config file not found: #{MINI_APPS_CONFIG_PATH}"
      return []
    end

    config = YAML.load_file(MINI_APPS_CONFIG_PATH)
    config["official_mini_apps"] || []
  rescue => e
    Rails.logger.error "Failed to load mini-apps config: #{e.message}"
    []
  end

  def self.sync_mini_apps
    yaml_apps = load_from_yaml
    synced_count = 0

    yaml_apps.each do |app_config|
      mini_app = sync_mini_app(app_config)
      if mini_app
        synced_count += 1
        Rails.logger.info "Synced mini-app: #{mini_app.app_id}"
      end
    end

    Rails.logger.info "Synced #{synced_count} mini-apps from YAML config"
    synced_count
  end

  def self.sync_mini_app(app_config)
    app_id = app_config["app_id"]

    # Find or create the mini-app
    mini_app = MiniApp.find_or_initialize_by(app_id: app_id)

    # Update attributes
    mini_app.assign_attributes(
      name: app_config["name"],
      description: app_config["description"],
      version: app_config["version"],
      classification: app_config["classification"],
      developer_name: app_config["developer_name"],
      manifest: app_config["manifest"],
      status: :active  # Official mini-apps are always active
    )

    # Save and return
    if mini_app.save
      mini_app
    else
      Rails.logger.error "Failed to save mini-app #{app_id}: #{mini_app.errors.full_messages.join(', ')}"
      nil
    end
  rescue => e
    Rails.logger.error "Failed to sync mini-app #{app_id}: #{e.message}"
    nil
  end

  def self.approve_official_mini_apps
    yaml_apps = load_from_yaml
    approved_count = 0

    yaml_apps.each do |app_config|
      app_id = app_config["app_id"]
      mini_app = MiniApp.find_by(app_id: app_id)

      if mini_app && mini_app.status != "active"
        # For official mini-apps loaded from YAML, just activate them
        mini_app.update!(status: "active")

        # Create OAuth application
        create_oauth_application(mini_app)

        approved_count += 1
        Rails.logger.info "Activated official mini-app: #{app_id}"
      end
    end

    Rails.logger.info "Activated #{approved_count} official mini-apps"
    approved_count
  end

  def self.create_oauth_application(miniapp)
    # Create Doorkeeper OAuth application for the mini-app
    oauth_app = Doorkeeper::Application.find_or_create_by!(uid: miniapp.app_id) do |app|
      app.name = miniapp.name
      app.secret = SecureRandom.hex(32)
      app.redirect_uri = miniapp.manifest["redirect_uris"].join("\n")
      app.scopes = miniapp.manifest["scopes"].join(" ")
      app.confidential = true
    end

    Rails.logger.info "Created OAuth application for mini-app #{miniapp.app_id}: #{oauth_app.uid}"

    oauth_app
  rescue => e
    Rails.logger.error "Failed to create OAuth application for mini-app #{miniapp.app_id}: #{e.message}"
    raise
  end
end
