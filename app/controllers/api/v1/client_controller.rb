class Api::V1::ClientController < Api::BaseController
  # TMCP Protocol Section 10.5: Capability Negotiation

  before_action :authenticate_tep_token

  # GET /api/v1/capabilities - TMCP Protocol Section 10.5.2
  def capabilities
    # Get platform from User-Agent or parameter
    platform = params[:platform] || detect_platform
    client_version = params[:client_version] || "unknown"

    capabilities = {
      capabilities: {
        camera: {
          available: true,
          requires_permission: true,
          supported_modes: [ "photo", "qr_scan", "video" ]
        },
        location: {
          available: true,
          requires_permission: true,
          accuracy: "high"
        },
        payment: {
          available: true,
          providers: [ "wallet", "card" ],
          max_amount: 50000.00
        },
        storage: {
          available: true,
          quota_bytes: 10485760, # 10MB
          persistent: true
        },
        messaging: {
          available: true,
          rich_cards: true,
          file_upload: true
        },
        biometric: {
          available: platform_supported_biometric?(platform),
          types: platform_biometric_types(platform)
        }
      },
      platform: {
        client_version: client_version,
        platform: platform,
        tmcp_version: "1.0"
      },
      features: {
        group_gifts: true,
        p2p_transfers: true,
        miniapp_payments: true
      }
    }

    render json: capabilities
  end

  # POST /api/v1/client/bootstrap - TMCP Protocol Section 16.8.2
  def bootstrap
    client_version = params[:client_version]
    platform = params[:platform] || detect_platform
    device_id = params[:device_id]

    # Get official mini-apps for this platform
    official_apps = MiniApp.active.where(classification: :official).map do |app|
      manifest = app.manifest || {}
      {
        miniapp_id: app.app_id,
        entry_url: manifest['entry_url'],
        bundle_url: (mini_app_package_url(app_id: app.app_id, version: app.version) if app.bundle.attached? && manifest.dig('bundle', 'version') == app.version),
        bundle_hash: manifest.dig('bundle', 'hash'),
        bundle_signature: manifest.dig('bundle', 'signature'),
        credentials: {
          client_id: app.app_id
        }
      }
    end

    render json: {
      bootstrap_id: "bootstrap_#{SecureRandom.hex(8)}",
      official_apps: official_apps
    }
  end

  # POST /api/v1/client/check-updates - TMCP Protocol Section 16.8.1
  def check_updates
    installed_apps = params[:installed_apps] || []
    platform = params[:platform] || detect_platform

    updates_available = []

    installed_apps.each do |installed_app|
      miniapp_id = installed_app["miniapp_id"]
      current_version = installed_app["current_version"]

      app = MiniApp.find_by(app_id: miniapp_id)
      next unless app&.active? && app.bundle.attached? && app.manifest.dig('bundle', 'version') == app.version

      if version_greater?(app.version, current_version)
        updates_available << {
          miniapp_id: miniapp_id,
          current_version: current_version,
          new_version: app.version,
          update_type: determine_update_type(current_version, app.version),
          mandatory: app.manifest&.dig("updates", "mandatory") || false,
          release_date: app.updated_at.iso8601,
          release_notes: app.manifest&.dig("changelog") || "Bug fixes and improvements",
          download: {
            url: mini_app_package_url(app_id: app.app_id, version: app.version),
            size_bytes: app.manifest.dig("bundle", "size_bytes"),
            hash: app.manifest.dig("bundle", "hash"),
            signature: app.manifest.dig("bundle", "signature")
          }
        }
      end
    end

    render json: { updates_available: updates_available }
  end

  private

  def authenticate_tep_token
    auth_header = request.headers["Authorization"]
    unless auth_header&.start_with?("Bearer ")
      return render json: { error: "missing_token", message: "TEP token required" }, status: :unauthorized
    end

    token = auth_header.sub("Bearer ", "")

    begin
      payload = TepTokenService.decode(token)
      user_id = payload["sub"]

      @current_user = User.find_by(matrix_user_id: user_id)
      unless @current_user
        render json: { error: "invalid_token", message: "User not found" }, status: :unauthorized
      end
    rescue JWT::DecodeError => e
      render json: { error: "invalid_token", message: e.message }, status: :unauthorized
    end
  end

  def detect_platform
    user_agent = request.user_agent || ""
    if user_agent.include?("Android")
      "android"
    elsif user_agent.include?("iPhone") || user_agent.include?("iPad")
      "ios"
    elsif user_agent.include?("Windows")
      "windows"
    elsif user_agent.include?("Mac")
      "macos"
    else
      "web"
    end
  end

  def platform_supported_biometric?(platform)
    case platform
    when "ios", "android"
      true
    else
      false
    end
  end

  def platform_biometric_types(platform)
    case platform
    when "ios"
      [ "fingerprint", "face" ]
    when "android"
      [ "fingerprint", "face", "iris" ]
    else
      []
    end
  end

  # Bootstrap distributes published app metadata. Tokens are obtained through
  # the existing OAuth + PKCE consent flow, never minted for an unrelated caller.

  def version_greater?(new_version, current_version)
    # Simple version comparison (in production, use proper semver)
    Gem::Version.new(new_version) > Gem::Version.new(current_version)
  rescue
    # Fallback for non-standard versions
    new_version != current_version
  end

  def determine_update_type(from_version, to_version)
    # Simple update type determination
    from_parts = from_version.split(".").map(&:to_i)
    to_parts = to_version.split(".").map(&:to_i)

    if to_parts[0] > from_parts[0]
      "major"
    elsif to_parts[1] > from_parts[1]
      "minor"
    else
      "patch"
    end
  rescue
    "minor"
  end
end
