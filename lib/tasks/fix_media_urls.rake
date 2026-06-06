# frozen_string_literal: true

namespace :social do
  desc "Regenerate thumbnail/playback URLs for all posts (run after switching to S3)"
  task fix_media_urls: :environment do
    # Set a dummy host for URL generation (won't be used with public S3,
    # but ActiveStorage requires it to be set)
    ActiveStorage::Current.url_options = { host: "https://app.tween.im" }

    fixed = 0
    skipped = 0
    failed = 0

    SocialPost.where.not(id: nil).find_each do |post|
      unless post.source_media.attached?
        skipped += 1
        next
      end

      begin
        url = post.source_media.url

        if post.content_type == "photo"
          post.update_column(:thumbnail_url, url)
        else
          # For video, keep the existing playback_url if it's already an HLS manifest,
          # otherwise use the direct source URL
          playback = if post.playback_url.present? && post.playback_url.end_with?(".m3u8")
            post.playback_url
          else
            url
          end
          post.update_columns(
            playback_url: playback,
            thumbnail_url: post.thumbnail_url.presence || url
          )
        end

        fixed += 1
        puts "✓ #{post.post_id} → #{url}"
      rescue => e
        failed += 1
        puts "✗ #{post.post_id}: #{e.message}"
      end
    end

    puts "\nDone: #{fixed} fixed, #{skipped} skipped (no attachment), #{failed} failed"
  end
end
