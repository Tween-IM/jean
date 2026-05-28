class CreateSocialBookmarks < ActiveRecord::Migration[8.1]
  def change
    create_table :social_bookmarks do |t|
      t.references :social_video, null: false, foreign_key: true
      t.string :user_id, null: false

      t.timestamps
    end

    add_index :social_bookmarks, [ :social_video_id, :user_id ], unique: true
    add_index :social_bookmarks, [ :user_id, :created_at ]
  end
end
