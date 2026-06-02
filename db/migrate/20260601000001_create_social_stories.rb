class CreateSocialStories < ActiveRecord::Migration[7.2]
  def change
    create_table :social_stories, id: :uuid do |t|
      t.string :story_id, null: false
      t.string :creator_user_id, null: false
      t.string :media_url
      t.string :media_type, null: false, default: "image"
      t.text :caption
      t.datetime :expires_at, null: false
      t.string :status, null: false, default: "active"
      t.timestamps
    end

    add_index :social_stories, :story_id, unique: true
    add_index :social_stories, :creator_user_id
    add_index :social_stories, [:status, :expires_at]
    add_index :social_stories, [:creator_user_id, :status, :expires_at], name: "idx_social_stories_creator_active"
  end
end
