# frozen_string_literal: true

# Permanently deletes stories that expired more than 7 days ago. We keep
# a 7-day buffer beyond `expires_at` so that "view count" or "highlights"
# features can still recover the row if/when added. Source media blobs
# are purged in the same pass so we don't leak storage on R2.
class ExpireSocialStoriesJob < ApplicationJob
  queue_as :default

  def perform
    cutoff = Time.current - 7.days

    expired = SocialStory.where("expires_at <= ?", cutoff)

    expired.find_each do |story|
      story.source_media.purge_later
      story.destroy!
    end
  end
end
