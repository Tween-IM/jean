class SocialVideoProcessingJob < ApplicationJob
  queue_as :default

  def perform(video)
    return unless video.source_video.attached?
    return if video.deleted?

    video.update!(
      playback_url: Rails.application.routes.url_helpers.rails_blob_path(video.source_video, only_path: true),
      status: "published",
      moderation_status: "approved",
      published_at: video.published_at || Time.current
    )
  end
end
