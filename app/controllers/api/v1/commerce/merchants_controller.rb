# frozen_string_literal: true

class Api::V1::Commerce::MerchantsController < Api::V1::Commerce::BaseController
  def create
    require_scope("commerce:merchant")

    merchant = ::CommerceMerchant.new(merchant_params)
    merchant.owner_user_id = @current_user.matrix_user_id
    merchant.miniapp_id = @miniapp_id

    if merchant.save
      render json: { merchant: merchant_json(merchant) }, status: :created
    else
      render_errors(merchant)
    end
  end

  def show
    require_scope("commerce:read")

    render json: { merchant: merchant_json(find_merchant) }
  end

  private

  def merchant_params
    params.require(:merchant).permit(:display_name, :status, :webhook_url)
  end
end
