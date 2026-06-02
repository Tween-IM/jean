# frozen_string_literal: true

require "open3"
require "fileutils"
require "shellwords"

# Transcodes a source MP4 to 2-rendition HLS (360p + 720p) using ffmpeg.
#
# Output layout:
#   {base_dir}/{post_id}/master.m3u8
#   {base_dir}/{post_id}/360p/index.m3u8  + 360p_*.ts
#   {base_dir}/{post_id}/720p/index.m3u8  + 720p_*.ts
#
# Returns a struct describing the master path, the public base URL for serving
# the playlist, and the variant metadata suitable for the post's `variants` field.
class HlsTranscodeService
  Result = Struct.new(:master_path, :public_base_url, :variants, :duration_seconds, keyword_init: true)

  RENDITIONS = [
    { name: "360p", height: 360, bitrate: "800k",  width: 640,  audio_bitrate: "96k" },
    { name: "720p", height: 720, bitrate: "2200k", width: 1280, audio_bitrate: "128k" }
  ].freeze

  SEGMENT_DURATION = 4 # seconds per .ts chunk

  class TranscodeError < StandardError; end

  def initialize(source_file:, post_id:, base_dir:, public_base_url:)
    @source_file = source_file
    @post_id = post_id
    @base_dir = base_dir
    @public_base_url = public_base_url.to_s.chomp("/")
  end

  def call
    raise TranscodeError, "source file missing: #{@source_file}" unless File.exist?(@source_file)

    output_root = File.join(@base_dir, @post_id)
    FileUtils.rm_rf(output_root)
    FileUtils.mkdir_p(output_root)

    variants = RENDITIONS.map { |r| transcode_rendition(r, output_root) }

    master = build_master_playlist(variants, output_root)

    Result.new(
      master_path: master,
      public_base_url: "#{@public_base_url}/#{@post_id}",
      variants: variants.map { |v| variant_metadata(v) },
      duration_seconds: probe_duration_seconds
    )
  end

  private

  def transcode_rendition(rendition, output_root)
    out_dir = File.join(output_root, rendition[:name])
    FileUtils.mkdir_p(out_dir)

    playlist = File.join(out_dir, "index.m3u8")
    segment_pattern = File.join(out_dir, "#{rendition[:name]}_%03d.ts")

    # scale=-2 preserves aspect ratio (even width), height capped to target
    vf = "scale=w=-2:h=#{rendition[:height]}:force_original_aspect_ratio=decrease"

    cmd = [
      "ffmpeg", "-y",
      "-i", @source_file,
      "-vf", vf,
      "-c:v", "libx264",
      "-preset", "veryfast",
      "-profile:v", "main",
      "-crf", "23",
      "-b:v", rendition[:bitrate],
      "-maxrate", rendition[:bitrate],
      "-bufsize", (rendition[:bitrate].to_i * 2).to_s,
      "-c:a", "aac",
      "-b:a", rendition[:audio_bitrate],
      "-ac", "2",
      "-hls_time", SEGMENT_DURATION.to_s,
      "-hls_playlist_type", "vod",
      "-hls_segment_filename", segment_pattern,
      "-hls_flags", "independent_segments",
      "-f", "hls",
      playlist
    ]

    out, err, status = Open3.capture3(*cmd)
    unless status.success?
      Rails.logger.error "[HlsTranscodeService] ffmpeg failed for #{rendition[:name]}: #{err.last(2000)}"
      raise TranscodeError, "ffmpeg failed for #{rendition[:name]}: #{err.lines.last(5).join}"
    end

    {
      name: rendition[:name],
      width: rendition[:width],
      height: rendition[:height],
      bitrate: rendition[:bitrate],
      playlist_path: playlist
    }
  end

  def build_master_playlist(variants, output_root)
    master_path = File.join(output_root, "master.m3u8")

    File.open(master_path, "w") do |f|
      f.puts "#EXTM3U"
      f.puts "#EXT-X-VERSION:3"
      variants.each do |v|
        bandwidth = v[:bitrate].to_s.gsub(/[^\d]/, "").to_i * 1000
        f.puts "#EXT-X-STREAM-INF:BANDWIDTH=#{bandwidth},RESOLUTION=#{v[:width]}x#{v[:height]}"
        f.puts "#{v[:name]}/index.m3u8"
      end
    end

    master_path
  end

  def variant_metadata(v)
    {
      "name" => v[:name],
      "url" => "#{v[:name]}/index.m3u8",
      "width" => v[:width],
      "height" => v[:height],
      "bitrate_kbps" => v[:bitrate].to_s.gsub(/[^\d]/, "").to_i,
      "format" => "hls"
    }
  end

  def probe_duration_seconds
    out, _err, status = Open3.capture3(
      "ffprobe", "-v", "error",
      "-show_entries", "format=duration",
      "-of", "default=noprint_wrappers=1:nokey=1",
      @source_file
    )
    return nil unless status.success?

    seconds = out.to_f
    seconds.positive? ? seconds.round : nil
  rescue StandardError
    nil
  end
end
