# frozen_string_literal: true

class Api::V1::Social::LikesController < Api::V1::Social::BaseController
  def create
    require_scope("social:engage")

    post = find_post
    return if ensure_post_visible(post)

    like = post.social_likes.find_or_create_by!(user_id: @current_user.matrix_user_id)
    emit_like_created(post) if like.previously_new_record?
    render json: { like_id: like.id, post: post_json(post.reload) }, status: :created
  end

  def destroy
    require_scope("social:engage")

    post = find_post
    like = post.social_likes.find_by(user_id: @current_user.matrix_user_id)
    like&.destroy!

    head :no_content
  end

  private

  def emit_like_created(post)
    MatrixEventService.publish_like_created(
      post_id: post.post_id,
      creator_id: post.creator_user_id,
      user_id: @current_user.matrix_user_id
    )

    NotificationService.create_like_notification(
      post: post,
      actor_user_id: @current_user.matrix_user_id,
      actor_display_name: current_creator_profile.display_name
    )
  end
end
