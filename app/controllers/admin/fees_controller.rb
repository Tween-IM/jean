# frozen_string_literal: true

module Admin
  # TweenPay's own fee schedule. Every row is a FeeConfiguration; editing here
  # changes what the payment services charge on the next transaction.
  class FeesController < BaseController
    before_action -> { require_admin_permission!(:manage_cards) }

    def index
      @fees = client.fee_configurations.fetch("fee_configurations")
    rescue ::Admin::RemoteClient::Unavailable, ::Admin::RemoteClient::Forbidden => error
      @fees = []
      @error = error.message
    end

    def update
      client.update_fee_configuration(params[:id], fee_params)
      redirect_to admin_fees_path, notice: "Fee updated."
    rescue ::Admin::RemoteClient::Unavailable, ::Admin::RemoteClient::Forbidden,
           ::Admin::RemoteClient::Rejected => error
      redirect_to admin_fees_path, alert: error.message
    end

    private

    def client
      TweenPay::AdminClient.new(current_admin_user)
    end

    def fee_params
      {
        fee_mode: params[:fee_mode].presence,
        fee_value: params[:fee_value],
        min_fee: params[:min_fee],
        max_fee: params[:max_fee],
        min_amount: params[:min_amount],
        max_amount: params[:max_amount],
        is_active: params[:is_active].present?
      }.compact
    end
  end
end
