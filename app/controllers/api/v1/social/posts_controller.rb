# frozen_string_literal: true

class Api::V1::Social::PostsController < Api::V1::Social::BaseController
  def create
    require_scope("social:write")

    attributes = post_params
    signed_blob_id = attributes.delete(:signed_blob_id)
    attributes[:media_upload_id] ||= signed_blob_id if signed_blob_id.present?

    post = current_creator_profile.social_posts.new(attributes)
    post.creator_user_id = @current_user.matrix_user_id

    if post.save
      attach_source_media(post, signed_blob_id)
      emit_post_published(post) if post.status == "published"
      render json: { post: post_json(post) }, status: :created
    else
      render_errors(post)
    end
  end

  def show
    require_scope("social:read")

    post = find_post
    return if ensure_post_visible(post)

    render json: { post: post_json(post) }
  end

  def update
    require_scope("social:write")

    post = find_post
    return if ensure_post_owner(post)

    if post.update(post_update_params)
      render json: { post: post_json(post) }
    else
      render_errors(post)
    end
  end

  def destroy
    require_scope("social:write")

    post = find_post
    return if ensure_post_owner(post)

    post.update!(status: "deleted", deleted_at: Time.current)
    emit_post_deleted(post)
    head :no_content
  end

  private

  def post_params
    params.require(:post).permit(:media_upload_id, :signed_blob_id, :caption, :playback_url, :thumbnail_url, :duration_seconds, :width, :height, :visibility, :status, :content_type, variants: [], commerce_refs: [])
  end

  def post_update_params
    params.require(:post).permit(:caption, :visibility, :status, commerce_refs: [])
  end

  def attach_source_media(post, signed_blob_id)
    return if signed_blob_id.blank?

    post.source_media.attach(signed_blob_id)

    if post.content_type == "photo"
      publish_photo_post(post)
    else
      post.update!(status: "processing")
      post.process_later
    end
  end

  def publish_photo_post(post)
    return unless post.source_media.attached?

    url_helpers = Rails.application.routes.url_helpers
    thumbnail_url = url_helpers.rails_blob_url(post.source_media, only_path: true)

    post.update!(
      thumbnail_url: thumbnail_url,
      status: "published",
      moderation_status: post.moderation_status.presence || "approved",
      published_at: post.published_at || Time.current
    )
    emit_post_published(post)
  end

  def emit_post_published(post)
    MatrixEventService.publish_post_published(
      post_id: post.post_id,
      content_type: post.content_type,
      creator_id: post.creator_user_id,
      caption: post.caption,
      thumbnail_url: post.thumbnail_url,
      published_at: post.published_at&.iso8601
    )
  end

  def emit_post_deleted(post)
    MatrixEventService.publish_post_deleted(
      post_id: post.post_id,
      creator_id: post.creator_user_id,
      deleted_at: post.deleted_at&.iso8601
    )
  end
end
