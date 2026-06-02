# frozen_string_literal: true

require "fileutils"

module HlsStorage
  # Copies the transcode work dir to a configurable local directory
  # and serves the master playlist from a configurable base URL.
  #
  # Defaults are tuned for development: the work dir is copied to
  # `public/hls` (served by Rails as a static asset) and the base
  # URL is the relative `/hls`. In a single-host production deploy,
  # override `base_dir` and `public_base_url` via `HLS_OUTPUT_DIR`
  # and `HLS_PUBLIC_BASE_URL` respectively.
  class Local
    attr_reader :base_dir, :public_base_url

    def initialize(base_dir: nil, public_base_url: nil)
      @base_dir = (base_dir || ENV.fetch("HLS_OUTPUT_DIR") do
        Rails.env.production? ? "/var/lib/tween/hls" : Rails.root.join("public", "hls").to_s
      end).to_s
      @public_base_url = (public_base_url || ENV.fetch("HLS_PUBLIC_BASE_URL", "/hls")).to_s.chomp("/")
    end

    # Copies every file under `work_dir` to `<base_dir>/<post_id>/`,
    # replacing any prior output for the same post.
    def persist(post_id:, work_dir:, **_opts)
      raise StorageError, "work_dir does not exist: #{work_dir}" unless File.directory?(work_dir)

      target = File.join(@base_dir, post_id)
      FileUtils.rm_rf(target)
      FileUtils.mkdir_p(target)
      FileUtils.cp_r(File.join(work_dir, "."), target)
    end

    # Public URL the client uses to fetch the master playlist.
    def public_url(post_id, filename = "master.m3u8")
      "#{@public_base_url}/#{post_id}/#{filename}"
    end
  end
end
