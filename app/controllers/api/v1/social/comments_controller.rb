# frozen_string_literal: true

class Api::V1::Social::CommentsController < Api::V1::Social::BaseController
  def index
    require_scope("social:read")

    video = find_video
    return if ensure_video_visible(video)

    comments = video.social_comments.active.chronologically.limit(limit_param(default: 30, max: 100))
    render json: { comments: comments.map { |comment| comment_json(comment) } }
  end

  def create
    require_scope("social:engage")

    video = find_video
    return if ensure_video_visible(video)

    comment = video.social_comments.new(comment_params)
    comment.author_user_id = @current_user.matrix_user_id

    if comment.save
      emit_comment_created(comment)
      render json: { comment: comment_json(comment), video: video_json(video.reload) }, status: :created
    else
      render_errors(comment)
    end
  end

  private

  def comment_params
    params.require(:comment).permit(:body, :parent_comment_id)
  end

  def emit_comment_created(comment)
    MatrixEventService.publish_comment_created(
      body: comment.body,
      video_id: comment.social_video.video_id,
      comment_id: comment.id,
      author_id: comment.author_user_id,
      creator_id: comment.social_video.creator_user_id
    )
  end
end
