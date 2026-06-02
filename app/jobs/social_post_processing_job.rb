# frozen_string_literal: true

# Transcodes a video post's source media into 2-rendition HLS.
#
# Idempotent: re-running overwrites the previous HLS output and re-updates
# the post's playback_url / variants / transcode_status consistently.
class SocialPostProcessingJob < ApplicationJob
  queue_as :default

  class TranscodeFailure < StandardError; end

  # Where HLS output is written. In dev/test this is a local public dir so
  # the files can be served directly. In production this is replaced with
  # an S3 bucket path.
  HLS_BASE_DIR = Rails.env.production? ? ENV.fetch("HLS_OUTPUT_DIR", "/var/lib/tween/hls") : Rails.root.join("public", "hls").to_s
  HLS_PUBLIC_BASE_URL = ENV.fetch("HLS_PUBLIC_BASE_URL", "/hls")

  def perform(post)
    return unless post.content_type == "video"
    return unless post.source_media.attached?
    return if post.deleted?

    Rails.logger.info "[SocialPostProcessingJob] Transcoding post=#{post.post_id}"

    post.update!(transcode_status: "processing", transcode_error: nil)

    source_path = download_source(post)
    begin
      result = HlsTranscodeService.new(
        source_file: source_path,
        post_id: post.post_id,
        base_dir: HLS_BASE_DIR,
        public_base_url: HLS_PUBLIC_BASE_URL
      ).call

      master_url = "#{result.public_base_url}/master.m3u8"

      update_attrs = {
        playback_url: master_url,
        hls_master_url: master_url,
        variants: result.variants,
        transcode_status: "ready",
        transcode_error: nil
      }
      update_attrs[:duration_seconds] = result.duration_seconds if result.duration_seconds
      post.update!(update_attrs)

      Rails.logger.info "[SocialPostProcessingJob] Transcoded post=#{post.post_id} -> #{master_url}"
    rescue HlsTranscodeService::TranscodeError => e
      Rails.logger.error "[SocialPostProcessingJob] Transcode failed for post=#{post.post_id}: #{e.message}"
      post.update!(
        transcode_status: "failed",
        transcode_error: e.message.truncate(500)
      )
      # Re-raise so the job framework can retry / dead-letter
      raise TranscodeFailure, e.message
    ensure
      File.delete(source_path) if source_path && File.exist?(source_path)
    end
  end

  private

  # Downloads the source blob to a temp file so ffmpeg can read it.
  # Returns the local path. Caller is responsible for cleanup.
  def download_source(post)
    blob = post.source_media.blob
    ext = blob.content_type&.start_with?("video/quicktime") ? "mov" : "mp4"
    temp_path = File.join(Dir.tmpdir, "hls_src_#{post.post_id}_#{SecureRandom.hex(4)}.#{ext}")
    File.open(temp_path, "wb") do |f|
      blob.download { |chunk| f.write(chunk) }
    end
    temp_path
  end
end
