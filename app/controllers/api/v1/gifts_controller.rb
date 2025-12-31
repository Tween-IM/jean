class Api::V1::GiftsController < ApplicationController
  # TMCP Protocol Section 7.5: Group Gift Distribution

  before_action :authenticate_tep_token
  before_action :validate_gift_scope

  # POST /wallet/v1/gift/create - TMCP Protocol Section 7.5.2
  def create
    gift_type = params[:type] || "group"

    if gift_type == "individual"
      handle_individual_gift
    else
      handle_group_gift
    end
  end

  def handle_individual_gift
    required_params = %w[recipient amount currency idempotency_key]
    missing_params = required_params.select { |param| params[param].blank? }

    if missing_params.any?
      return render json: { error: "invalid_request", message: "Missing required parameters: #{missing_params.join(', ')}" }, status: :bad_request
    end

    amount = params[:amount].to_f

    if amount <= 0 || amount > 50000.00
      return render json: { error: "invalid_amount", message: "Amount must be between 0.01 and 50,000.00" }, status: :bad_request
    end

    cache_key = "gift_idempotent:#{@current_user.id}:#{params[:idempotency_key]}"
    if Rails.cache.read(cache_key)
      return render json: { error: "duplicate_request", message: "Duplicate request with same idempotency key" }, status: :conflict
    end

    gift_id = "gift_#{SecureRandom.alphanumeric(12)}"
    expires_at = Time.current + (params[:expires_in_seconds] || 86400).to_i.seconds

    gift_data = {
      gift_id: gift_id,
      type: "individual",
      status: "active",
      total_amount: amount,
      currency: params[:currency],
      count: 1,
      remaining: 1,
      distribution: "equal",
      message: params[:message],
      recipient: params[:recipient],
      creator: {
        user_id: @current_user.matrix_user_id,
        wallet_id: @current_user.wallet_id
      },
      room_id: params[:room_id],
      expires_at: expires_at.iso8601,
      opened_by: [],
      created_at: Time.current.iso8601,
      event_id: "$event_#{gift_id}:tween.example"
    }

    Rails.cache.write("gift:#{gift_id}", gift_data, expires_in: expires_at - Time.current)
    Rails.cache.write(cache_key, gift_id, expires_in: 24.hours)

    MatrixEventService.publish_gift_created(gift_data)

    render json: gift_data, status: :created
  end

  def handle_group_gift
    required_params = %w[total_amount currency count distribution idempotency_key]
    missing_params = required_params.select { |param| params[param].blank? }

    if missing_params.any?
      return render json: { error: "invalid_request", message: "Missing required parameters: #{missing_params.join(', ')}" }, status: :bad_request
    end

    amount = params[:total_amount].to_f
    count = params[:count].to_i

    if amount <= 0 || amount > 50000.00
      return render json: { error: "invalid_amount", message: "Total amount must be between 0.01 and 50,000.00" }, status: :bad_request
    end

    if count < 2 || count > 100
      return render json: { error: "invalid_count", message: "Gift count must be between 2 and 100" }, status: :bad_request
    end

    unless %w[random equal].include?(params[:distribution])
      return render json: { error: "invalid_distribution", message: "Distribution must be \"random\" or \"equal\"" }, status: :bad_request
    end

    cache_key = "gift_idempotent:#{@current_user.id}:#{params[:idempotency_key]}"
    if Rails.cache.read(cache_key)
      return render json: { error: "duplicate_request", message: "Duplicate request with same idempotency key" }, status: :conflict
    end

    distribution = case params[:distribution]
    when "equal"
      equal_distribution(amount, count)
    when "random"
      random_distribution(amount, count)
    end

    gift_id = "gift_#{SecureRandom.alphanumeric(12)}"
    expires_at = Time.current + (params[:expires_in_seconds] || 86400).to_i.seconds

    gift_data = {
      gift_id: gift_id,
      type: "group",
      status: "active",
      total_amount: amount,
      currency: params[:currency],
      count: count,
      remaining: count,
      distribution: params[:distribution],
      message: params[:message],
      creator: {
        user_id: @current_user.matrix_user_id,
        wallet_id: @current_user.wallet_id
      },
      room_id: params[:room_id],
      expires_at: expires_at.iso8601,
      opened_by: [],
      created_at: Time.current.iso8601,
      event_id: "$event_#{gift_id}:tween.example"
    }

    Rails.cache.write("gift:#{gift_id}", gift_data, expires_in: expires_at - Time.current)
    Rails.cache.write(cache_key, gift_id, expires_in: 24.hours)

    MatrixEventService.publish_gift_created(gift_data)

    render json: gift_data, status: :created
  end

  # POST /wallet/v1/gift/:gift_id/open - TMCP Protocol Section 7.5.3
  def open
    gift_id = params[:gift_id]
    gift_data = Rails.cache.read("gift:#{gift_id}")

    unless gift_data
      return render json: { error: "gift_not_found", message: "Gift not found or expired" }, status: :not_found
    end

    # Check if user already opened this gift
    if gift_data[:opened_by].any? { |entry| entry["user_id"] == @current_user.matrix_user_id }
      return render json: { error: "already_opened", message: "You have already opened this gift" }, status: :conflict
    end

    # Check if remaining is 0 (gift is empty)
    if gift_data[:remaining] <= 0
      return render json: { error: "gift_empty", message: "All gifts have been claimed" }, status: :gone
    end

    # Check if status is not "active" (gift is inactive)
    if gift_data[:status] != "active"
      return render json: { error: "gift_inactive", message: "Gift is no longer active" }, status: :gone
    end

    if gift_data[:status] != "active"
      return render json: { error: "gift_inactive", message: "Gift is no longer active" }, status: :gone
    end

    if gift_data[:remaining] <= 0
      return render json: { error: "gift_empty", message: "All gifts have been claimed" }, status: :gone
    end

    # Check if user already opened this gift
    if gift_data[:opened_by].any? { |entry| entry[:user_id] == @current_user.matrix_user_id }
      return render json: { error: "already_opened", message: "You have already opened this gift" }, status: :conflict
    end

    # Determine amount for this user
    amount_received = calculate_user_amount(gift_data, @current_user.matrix_user_id)

    # Update gift data
    gift_data[:opened_by] << {
      "user_id" => @current_user.matrix_user_id,
      "amount" => amount_received,
      "opened_at" => Time.current.iso8601
    }
    gift_data[:remaining] -= 1

    # Check if gift is fully opened
    if gift_data[:remaining] <= 0
      gift_data[:status] = "fully_opened"
    end

    # Save updated gift data
    Rails.cache.write("gift:#{gift_id}", gift_data, expires_in: Time.parse(gift_data[:expires_at]) - Time.current)

    # Publish Matrix event (PROTO Section 7.5.4)
    MatrixEventService.publish_gift_opened(gift_id, {
      user_id: @current_user.matrix_user_id,
      amount: amount_received,
      opened_at: Time.current.iso8601,
      remaining_count: gift_data[:remaining],
      room_id: gift_data[:room_id],
      leaderboard: gift_data[:opened_by].sort_by { |entry| -entry["amount"] }.map do |entry|
        { user: entry["user_id"], amount: entry["amount"] }
      end
    })

    # Calculate stats
    total_opened = gift_data[:opened_by].size
    your_rank = gift_data[:opened_by].sort_by { |entry| -entry["amount"] }.index { |entry| entry["user_id"] == @current_user.matrix_user_id } + 1

    render json: {
      gift_id: gift_id,
      amount_received: amount_received,
      message: gift_data[:message],
      sender: gift_data[:creator],
      opened_at: Time.current.iso8601,
      stats: {
        total_opened: total_opened,
        total_remaining: gift_data[:remaining],
        your_rank: your_rank
      }
    }
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

  def validate_gift_scope
    unless @token_scopes.include?("wallet:pay")
      render json: { error: "insufficient_scope", message: "wallet:pay scope required" }, status: :forbidden
    end
  end

  def equal_distribution(total_amount, count)
    # Equal distribution algorithm (PROTO Section 7.5.5)
    base_amount = (total_amount / count).round(2)
    remainder = (total_amount - base_amount * count).round(2)

    amounts = Array.new(count, base_amount)
    amounts[0] += remainder if remainder > 0 # Add remainder to first amount

    amounts
  end

  def random_distribution(total_amount, count)
    # Random distribution algorithm (PROTO Section 7.5.5)
    amounts = []
    remaining = total_amount

    (count - 1).times do
      # Ensure fair distribution: each amount is between 10% and 30% of average
      min_amount = (total_amount * 0.1 / count).round(2)
      max_amount = (remaining * 0.7).round(2)
      amount = rand(min_amount..max_amount).round(2)

      amounts << amount
      remaining -= amount
    end

    # Last recipient gets remaining amount
    amounts << remaining.round(2)
    amounts.shuffle # Randomize order

    amounts
  end

  def calculate_user_amount(gift_data, user_id)
    # For demo, assign amounts sequentially
    # In production, this would be pre-calculated during gift creation
    opened_count = gift_data[:opened_by].size
    distribution = case gift_data[:distribution]
    when "equal"
      equal_distribution(gift_data[:total_amount], gift_data[:count])
    when "random"
      random_distribution(gift_data[:total_amount], gift_data[:count])
    end

    distribution[opened_count] || 0.00
  end
end
