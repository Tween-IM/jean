# frozen_string_literal: true

class SocialVideoProcessingJob < ApplicationJob
  queue_as :default

  def perform(video)
    return unless video.source_video.attached?
    return if video.deleted?

    Rails.application.routes.default_url_options = { protocol: "https:", host: ENV["HOST_URL"] || "cdn.tween.example" }

    generate_thumbnail(video)
    update_video_metadata(video)
    finalize(video)
  end

  private

  def generate_thumbnail(video)
    return unless video.source_video.video?
    return if !defined?(ImageProcessing::Video)

    thumbnail = ImageProcessing::Video
      .source(video.source_video)
      .resize_to_limit(720, 1280)
      .strip
      .profile("4:2:0")
    processed = thumbnail.call

    blob = ActiveStorage::Blob.create_after_direct_upload!(
      io: processed.file,
      filename: "#{video.video_id}_poster.jpg",
      content_type: "image/jpeg",
      byte_size: processed.file.size,
      checksum: Digest::MD5.file(processed.file.path)
    )
    blob.service.upload(blob.key, processed.file.open, checksum: blob.checksum)

    video.generated_thumbnail.attach blob
  rescue StandardError => e
    Rails.logger.warn "[SocialVideoProcessingJob] Thumbnail generation failed: #{e.message}"
  end

  def update_video_metadata(video)
    url_helpers = Rails.application.routes.url_helpers

    thumbnail_url = if video.generated_thumbnail.attached?
      url_helpers.rails_blob_url(video.generated_thumbnail, only_path: true)
    elsif video.thumbnail_url.blank?
      url_helpers.rails_blob_url(video.source_video, only_path: true) + "#thumbnail"
    else
      video.thumbnail_url
    end

    variants = build_variants(video, url_helpers)

    video.update!(
      playback_url: url_helpers.rails_blob_url(video.source_video, only_path: true),
      thumbnail_url: thumbnail_url,
      variants: variants,
      status: "published",
      moderation_status: video.moderation_status.presence || "approved",
      published_at: video.published_at || Time.current
    )
  end

  def build_variants(video, url_helpers)
    source_url = url_helpers.rails_blob_url(video.source_video, only_path: true)

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

  def finalize(video)
    return if video.moderation_status == "rejected"

    video.update!(status: "published", published_at: video.published_at || Time.current)

    MatrixEventService.publish_video_published(
      video_id: video.video_id,
      creator_id: video.creator_user_id,
      caption: video.caption,
      thumbnail_url: video.thumbnail_url,
      published_at: video.published_at.iso8601
    )
  end
end
