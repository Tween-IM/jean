# frozen_string_literal: true

class Api::V1::Commerce::ShippingProfilesController < Api::V1::Commerce::BaseController
  def index
    require_scope("commerce:merchant")

    merchant = find_merchant
    return if ensure_merchant_owner(merchant)

    profiles = merchant.commerce_shipping_profiles.order(:created_at)
    render json: { shipping_profiles: profiles.map { |sp| shipping_profile_json(sp) } }
  end

  def create
    require_scope("commerce:merchant")

    merchant = find_merchant
    return if ensure_merchant_owner(merchant)

    profile = merchant.commerce_shipping_profiles.new(shipping_profile_params)

    if profile.save
      render json: { shipping_profile: shipping_profile_json(profile) }, status: :created
    else
      render_errors(profile)
    end
  end

  def update
    require_scope("commerce:merchant")

    profile = find_shipping_profile
    return if ensure_merchant_owner(profile.commerce_merchant)

    if profile.update(shipping_profile_params)
      render json: { shipping_profile: shipping_profile_json(profile) }
    else
      render_errors(profile)
    end
  end

  def destroy
    require_scope("commerce:merchant")

    profile = find_shipping_profile
    return if ensure_merchant_owner(profile.commerce_merchant)

    profile.update!(status: "inactive")
    render json: { shipping_profile: shipping_profile_json(profile) }
  end

  def calculate
    require_scope("commerce:read")

    profile = find_shipping_profile

    result = profile.calculate_shipping(
      destination_country: params[:country] || "NG",
      destination_state: params[:state],
      weight_grams: params[:weight_grams]&.to_i,
      subtotal_cents: params[:subtotal_cents]&.to_i || 0
    )

    render json: { shipping: result }
  end

  private

  def shipping_profile_params
    params.require(:shipping_profile).permit(
      :name, :processing_time_days, :origin_warehouse_id,
      :free_shipping_threshold_cents, :status,
      zones: [:name, :currency, :rate_cents, :rate_per_gram_cents, :transit_days, countries: [], states: []]
    )
  end
end
