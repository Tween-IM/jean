class CreateSocialCreatorProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :social_creator_profiles do |t|
      t.string :user_id, null: false
      t.string :handle, null: false
      t.string :display_name
      t.string :avatar_url
      t.text :bio
      t.integer :follower_count, null: false, default: 0
      t.integer :following_count, null: false, default: 0
      t.integer :video_count, null: false, default: 0
      t.boolean :verified, null: false, default: false
      t.string :commerce_storefront_id

      t.timestamps
    end

    add_index :social_creator_profiles, :user_id, unique: true
    add_index :social_creator_profiles, :handle, unique: true
  end
end
