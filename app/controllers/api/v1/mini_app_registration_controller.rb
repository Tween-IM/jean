class Api::V1::MiniAppRegistrationController < ApplicationController
  before_action :authenticate_tep_token, only: [ :create ]
  before_action :validate_developer_token!, only: [ :create ]
  before_action :set_miniapp, only: [ :show, :update, :appeal, :submit_for_review ]

  def create
    registration_params = validate_registration_params(params)

    result = MiniAppRegistrationService.register(
      name: registration_params[:name],
      short_name: registration_params[:short_name],
      description: registration_params[:description],
      category: registration_params[:category],
      developer: registration_params[:developer],
      technical: registration_params[:technical],
      branding: registration_params[:branding],
      classification: registration_params[:classification],
      user_id: @current_user.matrix_user_id
    )

    render json: result, status: :created
  end

  def show
    if @miniapp.nil?
      render json: { error: "Mini-app not found" }, status: :not_found
      return
    end

    render json: {
      miniapp_id: @miniapp.app_id,
      name: @miniapp.name,
      short_name: @miniapp.short_name,
      description: @miniapp.description,
      category: @miniapp.category,
      classification: @miniapp.classification,
      status: @miniapp.status,
      developer: {
        company_name: @miniapp.developer_company,
        email: @miniapp.developer_email,
        website: @miniapp.developer_website
      },
      technical: {
        entry_url: @miniapp.entry_url,
        redirect_uris: @miniapp.redirect_uris || [],
        webhook_url: @miniapp.webhook_url,
        scopes_requested: @miniapp.requested_scopes || []
      },
      branding: {
        icon_url: @miniapp.icon_url,
        primary_color: @miniapp.primary_color
      },
      created_at: @miniapp.created_at.iso8601,
      updated_at: @miniapp.updated_at.iso8601
    }, status: :ok
  end

  def update
    if @miniapp.nil?
      render json: { error: "Mini-app not found" }, status: :not_found
      return
    end

    if @miniapp.developer_user_id != @current_user.matrix_user_id
      render json: { error: "Unauthorized" }, status: :forbidden
      return
    end

    if @miniapp.status != "draft" && @miniapp.status != "rejected"
      render json: { error: "Can only update draft or rejected mini-apps" }, status: :bad_request
      return
    end

    result = MiniAppRegistrationService.update(
      miniapp: @miniapp,
      params: params.permit(:name, :short_name, :description, :category, :technical, :branding)
    )

    render json: result, status: :ok
  end

  def submit_for_review
    if @miniapp.nil?
      render json: { error: "Mini-app not found" }, status: :not_found
      return
    end

    if @miniapp.developer_user_id != @current_user.matrix_user_id
      render json: { error: "Unauthorized" }, status: :forbidden
      return
    end

    result = MiniAppRegistrationService.submit_for_review(@miniapp)

    render json: result, status: :ok
  end

  def appeal
    if @miniapp.nil?
      render json: { error: "Mini-app not found" }, status: :not_found
      return
    end

    if @miniapp.status != "rejected"
      render json: { error: "Can only appeal rejected mini-apps" }, status: :bad_request
      return
    end

    result = MiniAppRegistrationService.submit_appeal(
      miniapp: @miniapp,
      reason: params[:reason],
      supporting_info: params[:supporting_info],
      user_id: @current_user.matrix_user_id
    )

    render json: result, status: :ok
  end

  def check_status
    miniapp_id = params[:miniapp_id]
    miniapp = MiniApp.find_by(app_id: miniapp_id)

    if miniapp.nil?
      render json: { error: "Mini-app not found" }, status: :not_found
      return
    end

    review_status = MiniAppReviewService.get_review_status(miniapp)

    render json: review_status, status: :ok
  end

  def automated_review
    miniapp_id = params[:miniapp_id]
    miniapp = MiniApp.find_by(app_id: miniapp_id)

    if miniapp.nil?
      render json: { error: "Mini-app not found" }, status: :not_found
      return
    end

    result = MiniAppReviewService.run_automated_checks(miniapp)

    render json: result, status: :ok
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

  def validate_developer_token!
    required_scopes = [ "developer:register" ]
    has_scope = required_scopes.any? { |s| @token_scopes.include?(s) }

    unless has_scope
      render json: {
        error: "Forbidden",
        error_description: "Missing required scope: developer:register"
      }, status: :forbidden
    end
  end

  def validate_registration_params(params)
    required_fields = [ :name, :short_name, :description, :category, :developer, :technical ]
    required_fields.each do |field|
      if params[field].blank?
        raise ArgumentError, "Missing required field: #{field}"
      end
    end

    {
      name: params[:name],
      short_name: params[:short_name],
      description: params[:description],
      category: params[:category],
      developer: params[:developer].to_h.symbolize_keys,
      technical: params[:technical].to_h.symbolize_keys,
      branding: (params[:branding] || {}).to_h.symbolize_keys,
      classification: params[:classification] || "community"
    }
  end

  def set_miniapp
    @miniapp = MiniApp.find_by(app_id: params[:miniapp_id])
  end
end
