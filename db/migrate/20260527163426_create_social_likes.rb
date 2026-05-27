class CreateSocialLikes < ActiveRecord::Migration[8.1]
  def change
    create_table :social_likes do |t|
      t.references :social_video, null: false, foreign_key: true
      t.string :user_id, null: false

      t.timestamps
    end

    add_index :social_likes, [ :social_video_id, :user_id ], unique: true
  end
end
