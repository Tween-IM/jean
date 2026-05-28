class CreateSocialViews < ActiveRecord::Migration[8.1]
  def change
    create_table :social_views do |t|
      t.references :social_video, null: false, foreign_key: true
      t.string :viewer_user_id, null: false
      t.string :session_id, null: false
      t.integer :watched_ms, null: false, default: 0
      t.boolean :completed, null: false, default: false
      t.datetime :viewed_at, null: false

      t.timestamps
    end

    add_index :social_views, [ :social_video_id, :viewer_user_id, :session_id ], unique: true, name: "index_social_views_once_per_session"
  end
end
