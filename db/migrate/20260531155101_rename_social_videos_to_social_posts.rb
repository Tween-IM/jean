# frozen_string_literal: true

class RenameSocialVideosToSocialPosts < ActiveRecord::Migration[8.1]
  def change
    # Rename table (Rails auto-renames indexes)
    rename_table :social_videos, :social_posts

    # Rename columns
    rename_column :social_posts, :video_id, :post_id
    rename_column :social_posts, :upload_id, :media_upload_id

    # Add content_type discriminator
    add_column :social_posts, :content_type, :string, null: false, default: "video"

    # Make video-specific columns nullable (photos won't have these)
    change_column_null :social_posts, :duration_seconds, true
    change_column_null :social_posts, :width, true
    change_column_null :social_posts, :height, true

    # Add content_type index
    add_index :social_posts, :content_type
  end
end
