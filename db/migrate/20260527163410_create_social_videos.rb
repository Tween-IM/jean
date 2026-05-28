class CreateSocialVideos < ActiveRecord::Migration[8.1]
  def change
    create_table :social_videos do |t|
      t.string :video_id, null: false
      t.string :creator_user_id, null: false
      t.string :upload_id, null: false
      t.string :playback_url
      t.string :thumbnail_url
      t.integer :duration_seconds
      t.integer :width
      t.integer :height
      t.json :variants, null: false, default: []
      t.text :caption
      t.string :visibility, null: false, default: "public"
      t.string :status, null: false, default: "processing"
      t.string :moderation_status, null: false, default: "pending"
      t.json :commerce_refs, null: false, default: []
      t.integer :view_count, null: false, default: 0
      t.integer :like_count, null: false, default: 0
      t.integer :comment_count, null: false, default: 0
      t.integer :share_count, null: false, default: 0
      t.datetime :published_at
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :social_videos, :video_id, unique: true
    add_index :social_videos, [ :creator_user_id, :created_at ]
    add_index :social_videos, [ :status, :moderation_status, :visibility ], name: "index_social_videos_feed_eligibility"
  end
end
