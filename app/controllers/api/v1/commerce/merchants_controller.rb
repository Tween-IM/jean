# frozen_string_literal: true

class Api::V1::Commerce::MerchantsController < Api::V1::Commerce::BaseController
  def index
    require_scope("commerce:read")

    merchants = ::CommerceMerchant.active.order(created_at: :desc).limit(50)
    render json: { merchants: merchants.map { |m| merchant_json(m, detail: :public) } }
  end

  def create
    require_scope("commerce:merchant")

    merchant = ::CommerceMerchant.new(merchant_params)
    merchant.owner_user_id = @current_user.matrix_user_id
    merchant.miniapp_id = @miniapp_id

    if merchant.save
      render json: { merchant: merchant_json(merchant, detail: :full) }, status: :created
    else
      render_errors(merchant)
    end
  end

  def show
    require_scope("commerce:read")

    render json: { merchant: merchant_json(find_merchant, detail: :public) }
  end

  def me
    require_scope("commerce:merchant")

    merchant = ::CommerceMerchant.find_by(owner_user_id: @current_user.matrix_user_id)
    if merchant
      render json: { merchant: merchant_json(merchant, detail: :full) }
    else
      render json: { merchant: nil }
    end
  end

  def update
    require_scope("commerce:merchant")

    merchant = find_merchant
    return if ensure_merchant_owner(merchant)

    if merchant.update(merchant_params)
      render json: { merchant: merchant_json(merchant, detail: :full) }
    else
      render_errors(merchant)
    end
  end

  private

  def merchant_params
    params.require(:merchant).permit(
      :display_name, :status, :webhook_url, :logo_url, :banner_url,
      :business_type, :registration_number, :phone, :email, :website,
      :address_line1, :address_line2, :city, :state, :country, :about,
      policies: {}, social_links: {}, payout_settings: {}
    )
  end
end
