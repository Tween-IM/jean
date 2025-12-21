require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module TmcpServer
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    # TMCP Protocol Security Configuration
    config.force_ssl = ENV["FORCE_SSL"] == "true"

    # API-only application
    config.api_only = true

    # Custom middleware for TMCP
    config.middleware.use Rack::Attack

    # Keycloak OAuth Integration
    config.keycloak = {
      server_url: ENV["KEYCLOAK_URL"] || "https://iam.tween.im",
      realm: ENV["KEYCLOAK_REALM"] || "tween",
      client_id: ENV["KEYCLOAK_CLIENT_ID"] || "tmcp-server",
      client_secret: ENV["KEYCLOAK_CLIENT_SECRET"],
      redirect_uri: ENV["TMCP_REDIRECT_URI"] || "https://tmcp.tween.im/api/v1/oauth2/callback"
    }

    # Session store for OAuth flow
    config.session_store :cookie_store, key: "_tmcp_session"

    # CORS configuration for mini-app access
    config.middleware.insert_before 0, Rack::Cors do
      allow do
        origins ENV["ALLOWED_ORIGINS"]&.split(",") || [ "https://tween.example" ]
        resource "*",
          headers: :any,
          methods: [ :get, :post, :put, :patch, :delete, :options, :head ],
          expose: [ "X-RateLimit-Remaining", "X-RateLimit-Reset" ]
      end
    end
  end
end
