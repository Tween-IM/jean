class CreateSocialStoryViews < ActiveRecord::Migration[7.2]
  def change
    create_table :social_story_views, id: :uuid do |t|
      t.references :social_story, null: false, foreign_key: true, type: :uuid
      t.string :viewer_user_id, null: false
      t.datetime :viewed_at, null: false
      t.timestamps
    end

    add_index :social_story_views, [:social_story_id, :viewer_user_id], unique: true, name: "idx_social_story_views_unique"
    add_index :social_story_views, :viewer_user_id
  end
end
