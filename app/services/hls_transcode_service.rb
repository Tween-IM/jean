# frozen_string_literal: true

require "open3"
require "fileutils"
require "shellwords"

# Transcodes a source MP4 to 2-rendition HLS (360p + 720p) using ffmpeg.
#
# The service is **storage-agnostic**: it writes its working output
# (master playlist, variant playlists, .ts segments) into a local
# directory supplied by the caller and returns metadata describing the
# layout. Persistence (local disk, S3, etc.) is the caller's job — see
# HlsStorage.
#
# Output layout inside `output_dir`:
#   output_dir/master.m3u8
#   output_dir/360p/index.m3u8  + 360p_*.ts
#   output_dir/720p/index.m3u8  + 720p_*.ts
#
# Returns a struct describing the master filename, the variant
# metadata suitable for the post's `variants` field, and the source
# duration probed via ffprobe.
class HlsTranscodeService
  Result = Struct.new(:master_filename, :variants, :duration_seconds, :thumbnail_filename, keyword_init: true)

  RENDITIONS = [
    { name: "360p", height: 360, bitrate: "800k",  width: 640,  audio_bitrate: "96k" },
    { name: "720p", height: 720, bitrate: "2200k", width: 1280, audio_bitrate: "128k" }
  ].freeze

  SEGMENT_DURATION = 4 # seconds per .ts chunk

  class TranscodeError < StandardError; end

  def initialize(source_file:, output_dir:)
    @source_file = source_file
    @output_dir = output_dir
  end

  def call
    raise TranscodeError, "source file missing: #{@source_file}" unless File.exist?(@source_file)

    FileUtils.mkdir_p(@output_dir)

    variants = RENDITIONS.map { |r| transcode_rendition(r) }
    build_master_playlist(variants)
    thumbnail_filename = generate_thumbnail

    Result.new(
      master_filename: "master.m3u8",
      variants: variants.map { |v| variant_metadata(v) },
      duration_seconds: probe_duration_seconds,
      thumbnail_filename: thumbnail_filename
    )
  end

  private

  def transcode_rendition(rendition)
    out_dir = File.join(@output_dir, rendition[:name])
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
      "-pix_fmt", "yuv420p",
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
      bitrate: rendition[:bitrate]
    }
  end

  def build_master_playlist(variants)
    master_path = File.join(@output_dir, "master.m3u8")

    File.open(master_path, "w") do |f|
      f.puts "#EXTM3U"
      f.puts "#EXT-X-VERSION:3"
      f.puts "#EXT-X-START:TIME-OFFSET=0"
      variants.each do |v|
        bandwidth = v[:bitrate].to_s.gsub(/[^\d]/, "").to_i * 1000
        f.puts "#EXT-X-STREAM-INF:BANDWIDTH=#{bandwidth},RESOLUTION=#{v[:width]}x#{v[:height]}"
        f.puts "#{v[:name]}/index.m3u8"
      end
    end
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

  # Extract a single poster frame at ~1 s (or 25 % for very short clips).
  # Writes thumbnail.jpg into output_dir so HlsStorage persists it
  # alongside the playlists and segments.
  def generate_thumbnail
    seek_seconds = [1, (probe_duration_seconds || 1) * 0.25].min
    thumb_path = File.join(@output_dir, "thumbnail.jpg")

    cmd = [
      "ffmpeg", "-y",
      "-ss", seek_seconds.to_s,
      "-i", @source_file,
      "-vf", "scale=480:-2",
      "-q:v", "2",
      "-frames:v", "1",
      thumb_path
    ]

    out, err, status = Open3.capture3(*cmd)
    unless status.success?
      Rails.logger.warn "[HlsTranscodeService] Thumbnail generation failed: #{err.lines.last(3).join}"
      return nil
    end

    "thumbnail.jpg"
  end
end
