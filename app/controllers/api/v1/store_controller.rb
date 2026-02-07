class Api::V1::StoreController < ApplicationController
  # TMCP Protocol Section 16.6: Mini-App Store Protocol

  before_action :authenticate_tep_token, except: [ :categories, :apps ]
  before_action :validate_store_access, only: [ :install, :uninstall ]

  # GET /api/v1/store/categories - TMCP Protocol Section 16.6.1
  def categories
    categories = [
      { id: "shopping", name: "Shopping", icon: "🛒", description: "E-commerce and retail apps" },
      { id: "finance", name: "Finance", icon: "💰", description: "Financial and payment apps" },
      { id: "social", name: "Social", icon: "👥", description: "Communication and social apps" },
      { id: "productivity", name: "Productivity", icon: "⚡", description: "Tools and productivity apps" },
      { id: "entertainment", name: "Entertainment", icon: "🎮", description: "Games and entertainment" },
      { id: "utilities", name: "Utilities", icon: "🔧", description: "Utility and helper apps" }
    ]

    render json: { categories: categories }
  end

  # GET /api/v1/store/apps - TMCP Protocol Section 16.6.1
  def apps
    # Parse query parameters
    category = params[:category]
    sort = params[:sort] || "popular"
    classification = params[:classification]
    limit = (params[:limit] || 20).to_i.clamp(1, 100)
    offset = (params[:offset] || 0).to_i

    # Build query
    query = MiniApp.where(status: :active)

    # Filter by category if specified
    if category.present? && category != "all"
      query = query.where("manifest->>'category' = ?", category)
    end

    # Filter by classification if specified
    if classification.present?
      query = query.where(classification: classification)
    end

    # Sort results
    case sort
    when "popular"
      query = query.order(install_count: :desc)
    when "recent"
      query = query.order(created_at: :desc)
    when "rating"
      # For now, sort by install count as proxy for rating
      query = query.order(install_count: :desc)
    when "name"
      query = query.order(name: :asc)
    end

    # Paginate
    total_count = query.count
    apps = query.limit(limit).offset(offset)

    # Format response
    app_data = apps.map do |app|
      manifest = app.manifest || {}
      {
        miniapp_id: app.app_id,
        name: app.name,
        classification: app.classification,
        category: manifest["category"],
        rating: {
          average: manifest["rating"] || 4.5,
          count: manifest["rating_count"] || 100
        },
        install_count: app.install_count || 0,
        icon_url: manifest["icon_url"] || "https://cdn.tween.example/icons/default.png",
        version: app.version,
        preinstalled: app.classification == "official" && manifest["preinstalled"],
        installed: @current_user ? current_user_installed?(app.app_id) : false,
        developer: manifest["developer"] || {}
      }
    end

    render json: {
      apps: app_data,
      pagination: {
        total: total_count,
        limit: limit,
        offset: offset,
        has_more: (offset + limit) < total_count
      }
    }
  end

  # GET /api/v1/store/apps/{miniapp_id} - TMCP Protocol Section 16.6.1.b
  def show
    miniapp_id = params[:miniapp_id]
    app = MiniApp.find_by(app_id: miniapp_id, status: :active)

    unless app
      return render json: { 
        error: "miniapp_not_found", 
        message: "Mini-app not found" 
      }, status: :not_found
    end

    # Format app data (same structure as apps list)
    manifest = app.manifest || {}
    app_data = {
      miniapp_id: app.app_id,
      name: app.name,
      short_name: manifest["short_name"] || app.name[0..15],
      description: app.description,
      long_description: manifest["long_description"] || app.description,
      classification: app.classification,
      category: manifest["category"],
      icon_url: manifest["icon_url"] || "https://cdn.tween.example/icons/default.png",
      marketing: {
        screenshots: manifest["screenshots"] || [],
        header_image: manifest["header_image"] || [],
        theme_color: manifest["theme_color"]
      },
      version: app.version,
      updated_at: app.updated_at || app.created_at,
      size: manifest["size"],
      developer: manifest["developer"] || {},
      rating: {
        average: manifest["rating"] || 4.5,
        count: manifest["rating_count"] || 100
      },
      install_count: app.install_count || 0,
      preinstalled: app.classification == "official" && manifest["preinstalled"],
      installed: @current_user ? current_user_installed?(app.app_id) : false,
      permissions: manifest["permissions"] || {}
    }

    render json: {
      apps: [app_data]
    }
  end

  # POST /api/v1/store/apps/{miniapp_id}/install - TMCP Protocol Section 16.6.2
  def install
    miniapp_id = params[:miniapp_id]
    app = MiniApp.find_by(app_id: miniapp_id, status: :active)

    unless app
      return render json: { error: "miniapp_not_found", message: "Mini-app not found or not available" }, status: :not_found
    end

    # Check if already installed
    if current_user_installed?(miniapp_id)
      return render json: { error: "already_installed", message: "Mini-app is already installed" }, status: :conflict
    end

    # Check if official app and removable
    if app.classification == "official" && app.manifest&.dig("preinstalled", "removable") == false
      return render json: { error: "not_removable", message: "This system app cannot be manually installed" }, status: :forbidden
    end

    # Create installation
    installation = MiniappInstallation.create!(
      user: @current_user,
      mini_app: app,
      version: app.version,
      installed_at: Time.current
    )

    # Publish Matrix event (PROTO Section 8.1.4)
    MatrixEventService.publish_miniapp_lifecycle_event(
      "installed",
      {
        app_id: miniapp_id,
        name: app.name,
        version: app.version,
        classification: app.classification
      },
      @current_user.matrix_user_id
    )

    render json: {
      miniapp_id: miniapp_id,
      status: "installed",
      install_id: installation.id,
      installed_at: installation.installed_at.iso8601
    }, status: :created
  end

  # DELETE /api/v1/store/apps/{miniapp_id}/install - TMCP Protocol Section 16.6.2
  def uninstall
    miniapp_id = params[:miniapp_id]
    app = MiniApp.find_by(app_id: miniapp_id)

    unless app
      return render json: { error: "miniapp_not_found", message: "Mini-app not found" }, status: :not_found
    end

    # Check if official app and removable
    if app.classification == "official" && app.manifest&.dig("preinstalled", "removable") == false
      return render json: {
        error: {
          code: "APP_NOT_REMOVABLE",
          message: "This system app cannot be removed"
        }
      }, status: :forbidden
    end

    # Find and destroy installation
    installation = MiniappInstallation.find_by(user: @current_user, mini_app: app)

    unless installation
      return render json: { error: "not_installed", message: "Mini-app is not installed" }, status: :not_found
    end

    installation.destroy

    # Publish Matrix event
    MatrixEventService.publish_miniapp_lifecycle_event(
      "uninstalled",
      {
        app_id: miniapp_id,
        version: app.version
      },
      @current_user.matrix_user_id
    )

    # Clean up storage data (PROTO Section 10.3.8)
    StorageService.cleanup_user_app_data(@current_user.id, miniapp_id)

    render json: {
      miniapp_id: miniapp_id,
      status: "uninstalled",
      uninstalled_at: Time.current.iso8601
    }
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
        return render json: { error: "invalid_token", message: "User not found" }, status: :unauthorized
      end

      @token_scopes = payload["scope"]&.split(" ") || []
    rescue JWT::DecodeError => e
      render json: { error: "invalid_token", message: e.message }, status: :unauthorized
    end
  end

  def validate_store_access
    # Store access doesn't require special scopes - all users can browse/install
    # But some operations might need specific scopes in the future
  end

  def current_user_installed?(miniapp_id)
    return false unless @current_user

    app = MiniApp.find_by(app_id: miniapp_id)
    return false unless app

    MiniappInstallation.exists?(user: @current_user, mini_app: app)
  end
end
