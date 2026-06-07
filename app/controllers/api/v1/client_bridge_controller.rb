# frozen_string_literal: true

class Api::V1::ClientBridgeController < Api::BaseController
  include Api::TepAuthenticatable

  before_action :authenticate_tep_token

  def handle_method
    method = params[:method]
    id = params[:id]
    result = call_method(method, params[:params] || {})

    render json: {
      jsonrpc: "2.0",
      id: id,
      result: result
    }
  rescue ClientBridgeError => e
    render json: {
      jsonrpc: "2.0",
      id: id,
      error: { code: e.code, message: e.message }
    }, status: e.status
  rescue Api::TepAuthenticatable::InsufficientScopeError => e
    render json: {
      jsonrpc: "2.0",
      id: id,
      error: { code: -32003, message: e.message }
    }, status: :forbidden
  rescue StandardError => e
    Rails.logger.error "[ClientBridge] Unexpected error: #{e.message}"
    render json: {
      jsonrpc: "2.0",
      id: id,
      error: { code: -32603, message: "Internal error" }
    }, status: :internal_server_error
  end

  private

  def call_method(method, params)
    case method
    when "tween.social.openVideo"
      open_social_video(params)
    when "tween.social.shareVideo"
      share_social_video(params)
    when "tween.social.openPost"
      open_social_post(params)
    when "tween.social.sharePost"
      share_social_post(params)
    when "tween.social.openCreator"
      open_creator(params)
    when "tween.social.createPost"
      create_post(params)
    when "tween.commerce.openProduct"
      open_commerce_product(params)
    when "tween.commerce.shareProduct"
      share_commerce_product(params)
    when "tween.commerce.startCheckout"
      start_checkout(params)
    when "tween.commerce.openOrder"
      open_order(params)
    else
      raise ClientBridgeError.new(-32601, "Method not found: #{method}")
    end
  end

  def open_social_post(params)
    require_scope("social:read")

    post_id = params[:post_id] || params[:video_id]
    raise ClientBridgeError.new(-32602, "post_id required") if post_id.blank?

    post = ::SocialPost.find_by!(post_id: post_id)
    raise ClientBridgeError.new(-32004, "Post not found", :not_found) unless post.visible_to?(@current_user)

    { opened: true, post_id: post_id, deep_link: "tween://social/post/#{post_id}" }
  end

  def open_social_video(params)
    require_scope("social:read")

    video_id = params[:video_id]
    raise ClientBridgeError.new(-32602, "video_id required") if video_id.blank?

    post = ::SocialPost.find_by!(post_id: video_id)
    raise ClientBridgeError.new(-32004, "Post not found", :not_found) unless post.visible_to?(@current_user)

    { opened: true, video_id: video_id, deep_link: "tween://social/video/#{video_id}" }
  end

  def share_social_post(params)
    require_scope("social:engage")

    post_id = params[:post_id] || params[:video_id]
    room_id = params[:room_id]
    raise ClientBridgeError.new(-32602, "post_id required") if post_id.blank?
    raise ClientBridgeError.new(-32602, "room_id required") if room_id.blank?

    post = ::SocialPost.find_by!(post_id: post_id)
    raise ClientBridgeError.new(-32004, "Post not found", :not_found) unless post.visible_to?(@current_user)

    share = post.social_shares.create!(
      user_id: @current_user.matrix_user_id,
      target: "matrix_room",
      room_id: room_id
    )

    { shared: true, share_id: share.id, room_id: room_id }
  end

  def share_social_video(params)
    share_social_post(params)
  end

  def open_creator(params)
    require_scope("social:read")

    creator_id = params[:creator_id]
    raise ClientBridgeError.new(-32602, "creator_id required") if creator_id.blank?

    ::SocialCreatorProfile.find_by!(user_id: creator_id)
    { opened: true, creator_id: creator_id, deep_link: "tween://social/creator/#{creator_id}" }
  end

  def create_post(_params)
    require_scope("social:write")

    { deep_link: "tween://social/create", upload_url: "/api/v1/social/uploads" }
  end

  def open_commerce_product(params)
    require_scope("commerce:read")

    product_id = params[:product_id]
    raise ClientBridgeError.new(-32602, "product_id required") if product_id.blank?

    product = ::CommerceProduct.find_by!(product_id: product_id)
    raise ClientBridgeError.new(-32004, "Product not found", :not_found) unless product.status == "active"

    { opened: true, product_id: product_id, deep_link: "tween://commerce/product/#{product_id}" }
  end

  def share_commerce_product(params)
    require_scope("commerce:read")

    product_id = params[:product_id]
    raise ClientBridgeError.new(-32602, "product_id required") if product_id.blank?

    { shared: true, product_id: product_id }
  end

  def start_checkout(params)
    require_scope("commerce:checkout")

    cart_id = params[:cart_id]
    raise ClientBridgeError.new(-32602, "cart_id required") if cart_id.blank?

    cart = ::CommerceCart.find_by!(cart_id: cart_id)
    raise ClientBridgeError.new(-32003, "Cart belongs to another buyer", :forbidden) unless cart.buyer_user_id == @current_user.matrix_user_id

    { cart_id: cart.cart_id, deep_link: "tween://commerce/checkout/start?cart_id=#{cart.cart_id}" }
  end

  def open_order(params)
    require_scope("commerce:orders")

    order_id = params[:order_id]
    raise ClientBridgeError.new(-32602, "order_id required") if order_id.blank?

    order = ::CommerceOrder.find_by!(order_id: order_id)
    allowed = order.buyer_user_id == @current_user.matrix_user_id || order.commerce_merchant&.owner_user_id == @current_user.matrix_user_id
    raise ClientBridgeError.new(-32003, "Order belongs to another account", :forbidden) unless allowed

    { opened: true, order_id: order_id, deep_link: "tween://commerce/order/#{order_id}" }
  end

  class ClientBridgeError < StandardError
    attr_reader :code, :status

    def initialize(code, message, status = :bad_request)
      super(message)
      @code = code
      @status = status
    end
  end
end
