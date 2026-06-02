# frozen_string_literal: true

# Persistence backend for HLS output produced by HlsTranscodeService.
#
# Two backends are supported:
#
#   HlsStorage::Local — copies the transcode work dir to a configurable
#                       local directory (default: public/hls in dev,
#                       HLS_OUTPUT_DIR in production). The public URL
#                       is served by Rails itself, which is fine for
#                       single-host deploys and local development.
#
#   HlsStorage::S3    — uploads the transcode work dir to the system
#                       S3 bucket under the `hls/<post_id>/` prefix.
#                       Uses the same AWS_* credentials as ActiveStorage.
#                       The public URL is a CDN base URL (CloudFront etc.)
#                       in front of the bucket. This is the right
#                       choice for multi-host deploys.
#
# Backend selection:
#
#   HlsStorage.for_environment — picks Local in dev/test, S3 in
#   production. Override with HLS_STORAGE_BACKEND=s3|local.
#
# Uses the same S3 credentials and bucket as ActiveStorage (uploads).
# HLS files are stored under the hls/ prefix in the same bucket.
# See config/storage.yml for the shared AWS_* env vars.
# Optional:
#   HLS_CDN_BASE_URL      — CDN base the client uses to fetch playlists
module HlsStorage
  class StorageError < StandardError; end

  module_function

  # Returns the appropriate backend for the current environment.
  def for_environment
    backend = ENV.fetch("HLS_STORAGE_BACKEND") do
      Rails.env.production? ? "s3" : "local"
    end
    case backend.to_s.downcase
    when "s3"   then S3.new
    when "local" then Local.new
    else
      raise StorageError, "Unknown HLS_STORAGE_BACKEND: #{backend.inspect}"
    end
  end
end
