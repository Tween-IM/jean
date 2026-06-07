# frozen_string_literal: true

class Api::V1::Social::CommentsController < Api::V1::Social::BaseController
  def index
    require_scope("social:read")

    post = find_post
    return if ensure_post_visible(post)

    # Return threaded comments: top-level first, with nested replies
    top_level = post.social_comments.active.where(parent_comment_id: nil).chronologically
    replies = post.social_comments.active.where.not(parent_comment_id: nil).chronologically

    # Index replies by parent for efficient nesting
    replies_by_parent = replies.group_by(&:parent_comment_id)

    render json: {
      comments: top_level.map { |comment| comment_json(comment, replies_by_parent) }
    }
  end

  def create
    require_scope("social:engage")

    post = find_post
    return if ensure_post_visible(post)

    comment = post.social_comments.new(comment_params)
    comment.author_user_id = @current_user.matrix_user_id

    if comment.save
      emit_comment_created(comment)
      render json: { comment: comment_json(comment), post: post_json(post.reload) }, status: :created
    else
      render_errors(comment)
    end
  end

  private

  def comment_params
    params.require(:comment).permit(:body, :parent_comment_id)
  end

  def comment_json(comment, replies_by_parent = nil)
    base = {
      comment_id: comment.id,
      post_id: comment.social_post.post_id,
      parent_comment_id: comment.parent_comment_id,
      author_user_id: comment.author_user_id,
      body: comment.body,
      status: comment.status,
      created_at: comment.created_at
    }

    # Include replies if replies_by_parent is provided
    if replies_by_parent
      child_replies = replies_by_parent[comment.id] || []
      base[:replies] = child_replies.map { |reply| comment_json(reply, replies_by_parent) }
      base[:reply_count] = child_replies.length
    end

    base
  end

  def emit_comment_created(comment)
    MatrixEventService.publish_comment_created(
      body: comment.body,
      post_id: comment.social_post.post_id,
      comment_id: comment.id,
      author_id: comment.author_user_id,
      creator_id: comment.social_post.creator_user_id
    )

    NotificationService.create_comment_notification(
      comment: comment,
      actor_user_id: @current_user.matrix_user_id,
      actor_display_name: current_creator_profile.display_name
    )
  end
end
