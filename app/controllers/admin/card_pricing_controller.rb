# frozen_string_literal: true

module Admin
  # TweenPay's own card pricing. Clover bills the organization for its
  # services; what a customer pays is TweenPay's decision and is managed here.
  class CardPricingController < BaseController
    before_action :require_manage_cards!

    def show
      @pricing = client.card_pricing.fetch("card_pricing")
    rescue ::Admin::RemoteClient::Unavailable, ::Admin::RemoteClient::Forbidden => error
      @error = error.message
      @pricing = {}
    end

    def update
      @pricing = client.update_card_pricing(
        markup_bps: percentage_to_bps(params[:markup_percent]),
        fixed_fee_minor: naira_to_minor(params[:fixed_fee]),
        issuance_fee_minor: naira_to_minor(params[:issuance_fee]),
        clover_issuance_cost_minor: naira_to_minor(params[:clover_issuance_cost])
      ).fetch("card_pricing")
      redirect_to admin_card_pricing_path,
                  notice: "Card pricing updated. New decisions and issuances use it."
    rescue ::Admin::RemoteClient::Unavailable, ::Admin::RemoteClient::Forbidden,
           ::Admin::RemoteClient::Rejected => error
      @error = error.message
      @pricing = params.slice(:markup_percent, :fixed_fee, :issuance_fee,
                              :clover_issuance_cost).to_h
      render :show, status: :unprocessable_entity
    end

    private

    def client
      TweenPay::AdminClient.new(current_admin_user)
    end

    def require_manage_cards!
      require_admin_permission!(:manage_cards)
    end

    def percentage_to_bps(value)
      return 0 if value.blank?

      (BigDecimal(value.to_s) * 100).round
    rescue ArgumentError
      0
    end

    def naira_to_minor(value)
      return 0 if value.blank?

      (BigDecimal(value.to_s) * 100).round
    rescue ArgumentError
      0
    end
  end
end
