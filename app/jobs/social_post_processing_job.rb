# frozen_string_literal: true

class SocialPostProcessingJob < ApplicationJob
  queue_as :default

  def perform(post)
    return unless post.content_type == "video"
    return unless post.source_media.attached?
    return if post.deleted?

    Rails.application.routes.default_url_options = { protocol: "https:", host: ENV["HOST_URL"] || "cdn.tween.example" }

    generate_thumbnail(post)
    update_post_metadata(post)
    finalize(post)
  end

  private

  def generate_thumbnail(post)
    return unless post.source_media.video?
    return if !defined?(ImageProcessing::Video)

    thumbnail = ImageProcessing::Video
      .source(post.source_media)
      .resize_to_limit(720, 1280)
      .strip
      .profile("4:2:0")
    processed = thumbnail.call

    blob = ActiveStorage::Blob.create_after_direct_upload!(
      io: processed.file,
      filename: "#{post.post_id}_poster.jpg",
      content_type: "image/jpeg",
      byte_size: processed.file.size,
      checksum: Digest::MD5.file(processed.file.path)
    )
    blob.service.upload(blob.key, processed.file.open, checksum: blob.checksum)

    post.generated_thumbnail.attach blob
  rescue StandardError => e
    Rails.logger.warn "[SocialPostProcessingJob] Thumbnail generation failed: #{e.message}"
  end

  def update_post_metadata(post)
    url_helpers = Rails.application.routes.url_helpers

    thumbnail_url = if post.generated_thumbnail.attached?
      url_helpers.rails_blob_url(post.generated_thumbnail, only_path: true)
    elsif post.thumbnail_url.blank?
      url_helpers.rails_blob_url(post.source_media, only_path: true) + "#thumbnail"
    else
      post.thumbnail_url
    end

    variants = build_variants(post, url_helpers)

    post.update!(
      playback_url: url_helpers.rails_blob_url(post.source_media, only_path: true),
      thumbnail_url: thumbnail_url,
      variants: variants,
      status: "published",
      moderation_status: post.moderation_status.presence || "approved",
      published_at: post.published_at || Time.current
    )
  end

  def build_variants(post, url_helpers)
    source_url = url_helpers.rails_blob_url(post.source_media, only_path: true)

    [
      {
        url: source_url,
        format: "mp4",
        bitrate: 2000,
        width: 720,
        height: 1280
      }
    ]
  end

  def finalize(post)
    return if post.moderation_status == "rejected"

    post.update!(status: "published", published_at: post.published_at || Time.current)

    MatrixEventService.publish_post_published(
      post_id: post.post_id,
      content_type: post.content_type,
      creator_id: post.creator_user_id,
      caption: post.caption,
      thumbnail_url: post.thumbnail_url,
      published_at: post.published_at.iso8601
    )
  end
end
