# frozen_string_literal: true

class RenameSocialVideosToSocialPosts < ActiveRecord::Migration[8.1]
  def up
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

  def down
    # Backfill NULLs before re-adding NOT NULL constraints
    execute <<-SQL.squish
      UPDATE social_posts
      SET height = 0, width = 0, duration_seconds = 0
      WHERE height IS NULL OR width IS NULL OR duration_seconds IS NULL
    SQL

    remove_index :social_posts, :content_type
    change_column_null :social_posts, :height, false
    change_column_null :social_posts, :width, false
    change_column_null :social_posts, :duration_seconds, false
    remove_column :social_posts, :content_type

    rename_column :social_posts, :media_upload_id, :upload_id
    rename_column :social_posts, :post_id, :video_id
    rename_table :social_posts, :social_videos
  end
end
