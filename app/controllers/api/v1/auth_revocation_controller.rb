class AuthRevocationsController < ApplicationController
  before_action :validate_tep_token!, except: [ :webhook ]
  before_action :set_miniapp, only: [ :create, :user_revoke ]

  def create
    revoked_scopes = parse_scopes(params[:scopes])
    user_id = @current_user.matrix_user_id
    miniapp_id = @miniapp&.miniapp_id || params[:miniapp_id]

    result = AuthRevocationService.revoke_permissions(
      user_id: user_id,
      miniapp_id: miniapp_id,
      scopes: revoked_scopes,
      reason: params[:reason] || "user_initiated"
    )

    render json: result, status: :ok
  end

  def user_revoke
    user_id = @current_user.matrix_user_id

    result = AuthRevocationService.user_revoke_all(
      user_id: user_id,
      miniapp_id: params[:miniapp_id]
    )

    render json: result, status: :ok
  end

  def webhook
    payload = request.body.read
    signature = request.headers["X-TMCP-Signature"]

    verified = WebhookService.verify_signature(payload, signature, webhook_secret)
    unless verified
      render json: { error: "Invalid signature" }, status: :unauthorized
      return
    end

    data = JSON.parse(payload)
    result = AuthRevocationService.handle_webhook(data)

    render json: result, status: :ok
  end

  private

  def parse_scopes(scopes_param)
    return [] if scopes_param.blank?
    scopes_param.is_a?(Array) ? scopes_param : scopes_param.split
  end

  def set_miniapp
    return if params[:miniapp_id].blank?
    @miniapp = MiniApp.find_by(miniapp_id: params[:miniapp_id])
  end

  def webhook_secret
    ENV.fetch("WEBHOOK_SECRET", "default_webhook_secret")
  end
end
