# ActiveStorage Public Host Override
# ==================================
# When using an S3-compatible service (R2, MinIO, DigitalOcean Spaces, etc.)
# the API endpoint (for presigned uploads) and the public-facing host (for
# reads) are often different:
#
#   - API endpoint:  https://<account>.r2.cloudflarestorage.com
#   - Public host:   https://r2.tween.im        (custom domain / CDN)
#
# Set ACTIVE_STORAGE_PUBLIC_HOST to the public-facing URL. If unset, ActiveStorage
# falls back to its default behavior (using the configured endpoint for both).
#
# Usage in storage.yml or env:
#   amazon:
#     service: S3
#     endpoint: https://api-endpoint.example.com       # raw S3 API
#     public: true
#
#   ACTIVE_STORAGE_PUBLIC_HOST=https://cdn.example.com  # public reads
#
Rails.application.config.to_prepare do
  next unless ENV["ACTIVE_STORAGE_PUBLIC_HOST"].present?

  require "active_storage/service/s3_service" unless defined?(ActiveStorage::Service::S3Service)

  ActiveStorage::Service::S3Service.prepend(Module.new do
    def public_url(key, **options)
      host = ENV["ACTIVE_STORAGE_PUBLIC_HOST"].to_s.chomp("/")
      "#{host}/#{key}"
    end
  end)
end
