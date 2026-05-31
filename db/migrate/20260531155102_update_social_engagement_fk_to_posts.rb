# frozen_string_literal: true

class UpdateSocialEngagementFkToPosts < ActiveRecord::Migration[8.1]
  def change
    %i[social_views social_likes social_comments social_bookmarks social_shares social_reports].each do |table|
      rename_column table, :social_video_id, :social_post_id
    end
  end
end
