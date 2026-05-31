# frozen_string_literal: true

class Api::V1::Social::BookmarksController < Api::V1::Social::BaseController
  def index
    require_scope("social:read")

    bookmarks = ::SocialBookmark.includes(:social_post).where(user_id: @current_user.matrix_user_id).order(created_at: :desc).limit(limit_param)
    render json: { bookmarks: bookmarks.map { |bookmark| bookmark_json(bookmark) } }
  end

  def create
    require_scope("social:engage")

    post = find_post
    return if ensure_post_visible(post)

    bookmark = post.social_bookmarks.find_or_create_by!(user_id: @current_user.matrix_user_id)
    render json: { bookmark: bookmark_json(bookmark), post: post_json(post) }, status: :created
  end

  def destroy
    require_scope("social:engage")

    post = find_post
    post.social_bookmarks.find_by(user_id: @current_user.matrix_user_id)&.destroy!
    head :no_content
  end
end
