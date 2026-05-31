# frozen_string_literal: true

class Api::V1::Social::SharesController < Api::V1::Social::BaseController
  def create
    require_scope("social:engage")

    post = find_post
    return if ensure_post_visible(post)

    share = post.social_shares.new(share_params)
    share.user_id = @current_user.matrix_user_id

    if share.save
      render json: { share: share_json(share), post: post_json(post.reload) }, status: :created
    else
      render_errors(share)
    end
  end

  private

  def share_params
    return ActionController::Parameters.new(target: "link").permit(:target) if params[:share].blank?

    params.require(:share).permit(:target, :room_id, metadata: {})
  end
end
