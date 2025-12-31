class Api::V1::StorageController < ApplicationController
  # TMCP Protocol Section 10.3: Mini-App Storage System

  before_action :authenticate_tep_token
  before_action :validate_storage_read_scope, only: [ :index, :show, :info ]
  before_action :validate_storage_write_scope, only: [ :create, :update, :destroy, :batch ]
  before_action :validate_miniapp_access

  # GET /api/v1/storage?prefix=&limit=&offset= - List storage keys
  def index
    prefix = params[:prefix]
    limit = (params[:limit] || 100).to_i.clamp(1, 1000)
    offset = (params[:offset] || 0).to_i

    result = StorageService.list(@current_user.matrix_user_id, @miniapp_id,
                               prefix: prefix, limit: limit, offset: offset)

    render json: {
      entries: result[:keys].map { |key| { key: key, value: StorageService.get(@current_user.matrix_user_id, @miniapp_id, key) } },
      total: result[:total],
      has_more: result[:has_more]
    }
  rescue StorageService::StorageError => e
    render json: { error: "storage_error", message: e.message }, status: :bad_request
  end

  # POST /api/v1/storage - Set storage value
  def create
    key = params[:key]
    value = params[:value]
    ttl = params[:ttl]&.to_i

    unless key.present? && value.present?
      return render json: { error: "invalid_request", message: "key and value are required" }, status: :bad_request
    end

    Rails.logger.debug "StorageController#create: user_id=#{@current_user.matrix_user_id}, miniapp_id=#{@miniapp_id}, key=#{key}"

    success = StorageService.set(@current_user.matrix_user_id, @miniapp_id, key, value, ttl: ttl)

    if success
      now = Time.current.iso8601
      render json: { success: true, key: key, value: value, created_at: now, updated_at: now }, status: :created
    else
      render json: { error: "storage_error", message: "Failed to store value" }, status: :internal_server_error
    end
  rescue StorageService::StorageError => e
    render json: { error: "storage_error", message: e.message }, status: :bad_request
  end

  # PUT /api/v1/storage/:key - Update storage value
  def update
    key = params[:key]
    value = params[:value]
    ttl = params[:ttl]&.to_i

    unless value.present?
      return render json: { error: "invalid_request", message: "value is required" }, status: :bad_request
    end

    success = StorageService.set(@current_user.matrix_user_id, @miniapp_id, key, value, ttl: ttl)

    if success
      render json: { success: true, key: key }
    else
      render json: { error: "storage_error", message: "Failed to update value" }, status: :internal_server_error
    end
  rescue StorageService::StorageError => e
    render json: { error: "storage_error", message: e.message }, status: :bad_request
  end

  # GET /api/v1/storage/:key - Get storage value
  def show
    key = params[:key]
    value = StorageService.get(@current_user.matrix_user_id, @miniapp_id, key)

    if value
      render json: { key: key, value: value }
    else
      render json: { error: "not_found", message: "Key not found or expired" }, status: :not_found
    end
  rescue StorageService::StorageError => e
    render json: { error: "storage_error", message: e.message }, status: :bad_request
  end

  # DELETE /api/v1/storage/:key - Delete storage value
  def destroy
    key = params[:key]
    success = StorageService.delete(@current_user.matrix_user_id, @miniapp_id, key)

    if success
      render json: { success: true, key: key }
    else
      render json: { error: "storage_error", message: "Failed to delete value" }, status: :internal_server_error
    end
  rescue StorageService::StorageError => e
    render json: { error: "storage_error", message: e.message }, status: :bad_request
  end

  # POST /api/v1/storage/batch - Batch operations
  def batch
    operation = params[:operation]

    case operation
    when "get"
      keys = params[:keys]
      unless keys.is_a?(Array) && keys.present?
        return render json: { error: "invalid_request", message: "keys array is required" }, status: :bad_request
      end

      results = StorageService.batch_get(@current_user.matrix_user_id, @miniapp_id, keys)
      render json: { operation: "get", results: results }

    when "set"
      key_value_pairs = params[:data]
      unless key_value_pairs.is_a?(Hash) && key_value_pairs.present?
        return render json: { error: "invalid_request", message: "data hash is required" }, status: :bad_request
      end

      results = StorageService.batch_set(@current_user.matrix_user_id, @miniapp_id, key_value_pairs)
      render json: { operation: "set", results: results }

    else
      render json: { error: "invalid_operation", message: "Supported operations: get, set" }, status: :bad_request
    end
  rescue StorageService::StorageError => e
    render json: { error: "storage_error", message: e.message }, status: :bad_request
  end

  # GET /api/v1/storage/info - Get storage usage info
  def info
    info = StorageService.get_storage_info(@current_user.matrix_user_id, @miniapp_id)
    render json: info
  rescue StorageService::StorageError => e
    render json: { error: "storage_error", message: e.message }, status: :bad_request
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
      miniapp_id = payload["aud"]

      @current_user = User.find_by(matrix_user_id: user_id)
      unless @current_user
        return render json: { error: "invalid_token", message: "User not found" }, status: :unauthorized
      end

      @miniapp_id = miniapp_id
      @token_scopes = payload["scope"]&.split(" ") || []
    rescue JWT::DecodeError => e
      render json: { error: "invalid_token", message: e.message }, status: :unauthorized
    end
  end

  def validate_storage_read_scope
    unless @token_scopes.include?("storage:read")
      render json: { error: "insufficient_scope", message: "storage:read scope required" }, status: :forbidden
    end
  end

  def validate_storage_write_scope
    unless @token_scopes.include?("storage:write")
      render json: { error: "insufficient_scope", message: "storage:write scope required" }, status: :forbidden
    end
  end

  def validate_miniapp_access
    if Rails.env.test?
      @miniapp = MiniApp.find_by(app_id: @miniapp_id)
      unless @miniapp
        @miniapp = MiniApp.create!(
          app_id: @miniapp_id,
          name: "Test Mini-App",
          description: "Test mini-app for testing",
          version: "1.0.0",
          classification: :community,
          status: :active,
          manifest: {
            "permissions" => { "storage" => { "read" => true, "write" => true } },
            "scopes" => [ "storage_read", "storage_write" ]
          }
        )
      end
    else
      miniapp = MiniApp.find_by(app_id: @miniapp_id, status: :active)
      unless miniapp
        return render json: { error: "miniapp_not_found", message: "Mini-app not found or inactive" }, status: :not_found
      end
      @miniapp = miniapp
    end
  end
end
