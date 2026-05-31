class RenameVideoCountToPostCountInSocialCreatorProfiles < ActiveRecord::Migration[8.1]
  def change
    rename_column :social_creator_profiles, :video_count, :post_count
  end
end
