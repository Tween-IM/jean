# frozen_string_literal: true

require "aws-sdk-s3"
require "fileutils"
require "pathname"

module HlsStorage
  # Uploads the transcode work dir to the system S3 bucket under the
  # `hls/<post_id>/` prefix and serves the master playlist from a
  # CDN base URL.
  #
  # Uses the same AWS_* credentials and bucket as ActiveStorage (uploads).
  # HLS files are namespaced under the hls/ prefix to keep them separate.
  #
  # Required env vars (shared with ActiveStorage):
  #   AWS_S3_BUCKET
  #   AWS_REGION
  #   AWS_ACCESS_KEY_ID
  #   AWS_SECRET_ACCESS_KEY
  # Optional:
  #   AWS_S3_ENDPOINT      — S3-compatible endpoint (MinIO, DO Spaces)
  #   HLS_CDN_BASE_URL     — CDN the client uses to fetch playlists
  class S3
    PREFIX = "hls"

    attr_reader :bucket, :region, :cdn_base_url

    def initialize(
      bucket: nil,
      region: nil,
      access_key_id: nil,
      secret_access_key: nil,
      endpoint: nil,
      cdn_base_url: nil,
      client: nil
    )
      @bucket            = bucket            || ENV.fetch("AWS_S3_BUCKET", "tween-uploads-#{Rails.env}")
      @region            = region            || ENV.fetch("AWS_REGION", "us-east-1")
      @access_key_id     = access_key_id     || ENV.fetch("AWS_ACCESS_KEY_ID")
      @secret_access_key = secret_access_key || ENV.fetch("AWS_SECRET_ACCESS_KEY")
      @endpoint          = endpoint          || ENV["AWS_S3_ENDPOINT"].presence
      @cdn_base_url      = (cdn_base_url     || ENV["HLS_CDN_BASE_URL"]).to_s.chomp("/")
      @client            = client
    end

    # Uploads every file under `work_dir` to `<bucket>/hls/<post_id>/`.
    # Replaces any prior output for the same post (object keys are
    # deterministic, so PutObject overwrites). For a clean reset, set
    # `delete_existing: true` to also issue a DeleteObjects call for
    # any keys already in the prefix.
    def persist(post_id:, work_dir:, delete_existing: false, **_opts)
      raise StorageError, "work_dir does not exist: #{work_dir}" unless File.directory?(work_dir)

      client = s3_client
      prefix = "#{PREFIX}/#{post_id}/"

      if delete_existing
        existing = client.list_object_versions(bucket: @bucket, prefix: prefix).to_h
        versions = existing[:versions] || []
        if versions.any?
          client.delete_objects(bucket: @bucket, delete: {
            objects: versions.map { |v| { key: v[:key], version_id: v[:version_id] } },
            quiet: true
          })
        end
      end

      Dir.glob(File.join(work_dir, "**", "*"), File::FNM_DOTMATCH).each do |path|
        next if File.directory?(path)

        rel = Pathname.new(path).relative_path_from(Pathname.new(work_dir)).to_s
        key = "#{prefix}#{rel}"

        client.put_object(
          bucket: @bucket,
          key: key,
          body: File.open(path),
          content_type: content_type_for(path),
          cache_control: "public, max-age=31536000, immutable"
        )
      end
    end

    # Public URL the client uses to fetch the master playlist.
    # Prefers HLS_CDN_BASE_URL (CDN-fronted) when set, otherwise
    # falls back to the virtual-hosted–style S3 URL.
    def public_url(post_id, filename = "master.m3u8")
      key = "#{PREFIX}/#{post_id}/#{filename}"
      if @cdn_base_url.present?
        return "#{@cdn_base_url}/#{key}"
      end
      "https://#{@bucket}.s3.#{@region}.amazonaws.com/#{key}"
    end

    private

    def s3_client
      @client ||= Aws::S3::Client.new(
        region: @region,
        access_key_id: @access_key_id,
        secret_access_key: @secret_access_key,
        endpoint: @endpoint,
        force_path_style: @endpoint.present?
      )
    end

    EXT_CONTENT_TYPES = {
      ".m3u8" => "application/vnd.apple.mpegurl",
      ".ts"   => "video/mp2t"
    }.freeze

    def content_type_for(path)
      ext = File.extname(path).downcase
      EXT_CONTENT_TYPES[ext] || "application/octet-stream"
    end
  end
end
