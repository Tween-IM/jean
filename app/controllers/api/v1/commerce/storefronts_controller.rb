class Api::V1::Commerce::StorefrontsController < Api::V1::Commerce::BaseController
  def index
    require_scope("commerce:read")

    storefronts = ::CommerceStorefront.includes(:commerce_merchant).order(created_at: :desc).limit(50)
    storefronts = storefronts.joins(:commerce_merchant).where(commerce_merchants: { merchant_id: params[:merchant_id] }) if params[:merchant_id].present?

    render json: { storefronts: storefronts.map { |storefront| storefront_json(storefront) } }
  end

  def create
    require_scope("commerce:merchant")

    merchant = find_merchant
    return if ensure_merchant_owner(merchant)

    storefront = merchant.commerce_storefronts.new(storefront_params)

    if storefront.save
      render json: { storefront: storefront_json(storefront) }, status: :created
    else
      render_errors(storefront)
    end
  end

  def show
    require_scope("commerce:read")

    render json: { storefront: storefront_json(find_storefront) }
  end

  def update
    require_scope("commerce:merchant")

    storefront = find_storefront
    return if ensure_merchant_owner(storefront.commerce_merchant)

    if storefront.update(storefront_params)
      render json: { storefront: storefront_json(storefront) }
    else
      render_errors(storefront)
    end
  end

  private

  def find_storefront
    ::CommerceStorefront.find_by!(storefront_id: params[:id])
  end

  def storefront_params
    params.require(:storefront).permit(:display_name, :slug, :description, :status)
  end
end
