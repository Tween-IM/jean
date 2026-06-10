# frozen_string_literal: true

class Api::V1::Commerce::PayoutsController < Api::V1::Commerce::BaseController
  def index
    require_scope("commerce:merchant")

    merchant = current_merchant
    return render json: { error: "not_found", message: "Merchant not found" }, status: :not_found unless merchant

    payouts = merchant.commerce_payouts.order(created_at: :desc).limit(limit_param(default: 20, max: 100))

    render json: {
      payouts: payouts.map { |p| payout_json(p) },
      meta: { total: merchant.commerce_payouts.count }
    }
  end

  def create
    require_scope("commerce:merchant")

    merchant = current_merchant
    return render json: { error: "not_found", message: "Merchant not found" }, status: :not_found unless merchant

    amount_cents = payout_params[:amount_cents].to_i
    if amount_cents <= 0
      return render json: { error: "invalid_amount", message: "Amount must be greater than 0" }, status: :bad_request
    end

    # Validate merchant has sufficient balance
    begin
      balance_info = WalletService.get_balance(@current_user.matrix_user_id, @tep_token)
      available_balance = (balance_info.dig(:balance, :available) || 0) * 100

      if available_balance < amount_cents
        return render json: { error: "insufficient_balance", message: "Insufficient wallet balance for payout" }, status: :unprocessable_entity
      end
    rescue WalletService::WalletError => e
      Rails.logger.error "[PayoutsController] Balance check failed for merchant #{merchant.merchant_id}: #{e.message}"
      return render json: { error: "balance_check_failed", message: "Could not verify wallet balance" }, status: :service_unavailable
    end

    payout = merchant.commerce_payouts.create!(
      amount_cents: amount_cents,
      currency: payout_params[:currency] || "NGN",
      payout_method: payout_params[:payout_method] || "bank_transfer",
      destination_account_number: payout_params[:destination_account_number],
      destination_bank_code: payout_params[:destination_bank_code],
      destination_bank_name: payout_params[:destination_bank_name],
      status: "pending"
    )

    # Initiate payout via wallet service
    begin
      result = WalletService.initiate_payout(
        wallet_id: merchant.wallet_id,
        amount: amount_cents / 100.0,
        currency: payout.currency,
        bank_account: {
          account_number: payout.destination_account_number,
          bank_code: payout.destination_bank_code,
          bank_name: payout.destination_bank_name
        },
        reference_id: payout.reference_id,
        tep_token: @tep_token
      )

      if result.is_a?(Hash) && (result["reference"] || result[:reference] || result["status"] == "processing")
        payout.update!(
          status: "processing",
          metadata: payout.metadata.merge("wallet_response" => result),
          processed_at: Time.current
        )
      else
        payout.update!(
          status: "failed",
          metadata: payout.metadata.merge("wallet_error" => result.inspect)
        )
        return render json: { error: "payout_failed", message: "Wallet service could not process payout" }, status: :unprocessable_entity
      end
    rescue WalletService::WalletError => e
      payout.update!(
        status: "failed",
        metadata: payout.metadata.merge("wallet_error" => e.message, "error_code" => e.code)
      )
      return render json: { error: "payout_failed", message: "Wallet service error: #{e.message}" }, status: :unprocessable_entity
    end

    render json: { payout: payout_json(payout) }, status: :created
  end

  private

  def payout_params
    params.require(:payout).permit(
      :amount_cents, :currency, :payout_method,
      :destination_account_number, :destination_bank_code, :destination_bank_name
    )
  end

  def limit_param(default:, max:)
    [(params[:limit] || default).to_i, max].min
  end

  def payout_json(payout)
    {
      payout_id: payout.payout_id,
      merchant_id: payout.commerce_merchant.merchant_id,
      amount_cents: payout.amount_cents,
      currency: payout.currency,
      status: payout.status,
      payout_method: payout.payout_method,
      destination: {
        account_number: mask_account(payout.destination_account_number),
        bank_code: payout.destination_bank_code,
        bank_name: payout.destination_bank_name
      },
      reference_id: payout.reference_id,
      processed_at: payout.processed_at&.iso8601,
      completed_at: payout.completed_at&.iso8601,
      created_at: payout.created_at.iso8601
    }
  end

  def mask_account(account_number)
    return nil if account_number.blank?
    return account_number if account_number.length <= 4

    "*" * (account_number.length - 4) + account_number[-4..]
  end

  def current_merchant
    @current_merchant ||= ::CommerceMerchant.find_by(owner_user_id: @current_user.matrix_user_id)
  end
end
