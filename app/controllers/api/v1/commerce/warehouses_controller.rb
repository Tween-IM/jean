# frozen_string_literal: true

class Api::V1::Commerce::WarehousesController < Api::V1::Commerce::BaseController
  def index
    require_scope("commerce:merchant")

    merchant = find_merchant
    return if ensure_merchant_owner(merchant)

    warehouses = merchant.commerce_warehouses.order(:created_at)
    render json: { warehouses: warehouses.map { |w| warehouse_json(w) } }
  end

  def create
    require_scope("commerce:merchant")

    merchant = find_merchant
    return if ensure_merchant_owner(merchant)

    warehouse = merchant.commerce_warehouses.new(warehouse_params)

    if warehouse.save
      render json: { warehouse: warehouse_json(warehouse) }, status: :created
    else
      render_errors(warehouse)
    end
  end

  def update
    require_scope("commerce:merchant")

    warehouse = find_warehouse
    return if ensure_merchant_owner(warehouse.commerce_merchant)

    if warehouse.update(warehouse_params)
      render json: { warehouse: warehouse_json(warehouse) }
    else
      render_errors(warehouse)
    end
  end

  def destroy
    require_scope("commerce:merchant")

    warehouse = find_warehouse
    return if ensure_merchant_owner(warehouse.commerce_merchant)

    warehouse.update!(status: "inactive")
    render json: { warehouse: warehouse_json(warehouse) }
  end

  private

  def warehouse_params
    params.require(:warehouse).permit(
      :name, :address_line1, :address_line2, :city, :state,
      :postal_code, :country, :phone, :is_default, :status
    )
  end
end
