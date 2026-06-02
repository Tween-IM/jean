# frozen_string_literal: true

# Transcodes a video post's source media into 2-rendition HLS and
# persists the result via the configured HlsStorage backend.
#
# Idempotent: re-running re-uploads to the same key prefix, replacing
# any prior output for the post.
class SocialPostProcessingJob < ApplicationJob
  queue_as :default

  class TranscodeFailure < StandardError; end

  def perform(post)
    return unless post.content_type == "video"
    return unless post.source_media.attached?
    return if post.deleted?

    Rails.logger.info "[SocialPostProcessingJob] Transcoding post=#{post.post_id}"

    post.update!(transcode_status: "processing", transcode_error: nil)

    storage = HlsStorage.for_environment
    source_path = download_source(post)

    Dir.mktmpdir("hls_#{post.post_id}_") do |work_dir|
      begin
        result = HlsTranscodeService.new(
          source_file: source_path,
          output_dir: work_dir
        ).call

        storage.persist(post_id: post.post_id, work_dir: work_dir)
        master_url = storage.public_url(post.post_id, result.master_filename)

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
      rescue HlsTranscodeService::TranscodeError, HlsStorage::StorageError => e
        Rails.logger.error "[SocialPostProcessingJob] Failed for post=#{post.post_id}: #{e.message}"
        post.update!(
          transcode_status: "failed",
          transcode_error: e.message.truncate(500)
        )
        # Re-raise so the job framework can retry / dead-letter
        raise TranscodeFailure, e.message
      end
    end
  ensure
    File.delete(source_path) if source_path && File.exist?(source_path)
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
