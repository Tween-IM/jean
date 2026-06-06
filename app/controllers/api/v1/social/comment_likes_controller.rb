# frozen_string_literal: true

class Api::V1::Social::CommentLikesController < Api::V1::Social::BaseController
  def create
    require_scope("social:engage")

    comment = find_comment
    like = comment.social_comment_likes.find_or_create_by!(user_id: @current_user.matrix_user_id)
    render json: { like_id: like.id, like_count: comment.social_comment_likes.count }, status: :created
  rescue ActiveRecord::RecordNotUnique
    render json: { like_count: comment.social_comment_likes.count }, status: :created
  end

  def destroy
    require_scope("social:engage")

    comment = find_comment
    like = comment.social_comment_likes.find_by(user_id: @current_user.matrix_user_id)
    like&.destroy!

    render json: { like_count: comment.social_comment_likes.count }, status: :ok
  end

  private

  def find_comment
    ::SocialComment.find(params[:comment_id])
  end
end
