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
require "rails/test_unit/railtie"

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

    # Matrix Authentication Service (MAS) Integration (PROTO Section 4.2)
    config.mas = {
      server_url: ENV["MAS_URL"] || "https://mas.tween.example",
      client_id: ENV["MAS_CLIENT_ID"] || "01KR77B4VPRHJD3A35J7W0609M",
      client_secret: ENV["MAS_CLIENT_SECRET"],
      token_url: ENV["MAS_TOKEN_URL"] || "https://mas.tween.example/oauth2/token",
      introspection_url: ENV["MAS_INTROSPECTION_URL"] || "https://mas.tween.example/oauth2/introspect",
      revocation_url: ENV["MAS_REVOCATION_URL"] || "https://mas.tween.example/oauth2/revoke"
    }

    # Session store for OAuth flow and admin dashboard
    config.session_store :cookie_store, key: "_tmcp_session"

    # Enable cookie/session/flash middleware for admin dashboard in api-only app
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore, key: "_tmcp_session"
    config.middleware.use ActionDispatch::Flash

    # CORS configuration for mini-app access
    config.middleware.insert_before 0, Rack::Cors do
      allow do
        if Rails.env.development?
          origins "*"
        else
          origins ENV["ALLOWED_ORIGINS"]&.split(",") || [ "https://tween.example" ]
        end
        resource "*",
          headers: :any,
          methods: [ :get, :post, :put, :patch, :delete, :options, :head ],
          expose: [ "X-RateLimit-Remaining", "X-RateLimit-Reset" ]
      end
    end
  end
end
