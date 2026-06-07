# frozen_string_literal: true

class Api::V1::Commerce::ReviewsController < Api::V1::Commerce::BaseController
  def index
    require_scope("commerce:read")

    if params[:product_id].present?
      product = ::CommerceProduct.find_by!(product_id: params[:product_id])
      reviews = product.commerce_reviews.approved.order(created_at: :desc)
    elsif params[:storefront_id].present?
      storefront = ::CommerceStorefront.find_by!(storefront_id: params[:storefront_id])
      reviews = ::CommerceReview.approved.where(commerce_merchant_id: storefront.commerce_merchant_id).order(created_at: :desc)
    else
      reviews = ::CommerceReview.approved.order(created_at: :desc)
    end

    reviews = reviews.limit(limit_param(default: 20, max: 100))

    render json: {
      reviews: reviews.map { |r| review_json(r) },
      meta: { total: reviews.count }
    }
  end

  def create
    require_scope("commerce:orders")

    product = ::CommerceProduct.find_by!(product_id: params[:product_id])

    # Verify purchase
    has_purchased = ::CommerceOrder.exists?(
      buyer_user_id: @current_user.matrix_user_id,
      commerce_merchant: product.commerce_merchant,
      status: %w[paid processing fulfilled]
    )

    unless has_purchased
      return render json: { error: "unauthorized", message: "You must purchase this product before reviewing" }, status: :forbidden
    end

    # Check for existing review
    existing = ::CommerceReview.find_by(
      buyer_user_id: @current_user.matrix_user_id,
      commerce_product: product
    )

    if existing
      return render json: { error: "duplicate", message: "You have already reviewed this product" }, status: :unprocessable_entity
    end

    review = product.commerce_reviews.new(review_params)
    review.commerce_merchant = product.commerce_merchant
    review.buyer_user_id = @current_user.matrix_user_id

    if review.save
      render json: { review: review_json(review) }, status: :created
    else
      render_errors(review)
    end
  end

  def helpful
    require_scope("commerce:read")

    review = find_review
    review.increment!(:helpful_count)

    render json: { review: review_json(review) }
  end

  private

  def review_params
    params.require(:review).permit(:rating, :title, :body)
  end

  def limit_param(default:, max:)
    [ (params[:limit] || default).to_i, max ].min
  end
end
