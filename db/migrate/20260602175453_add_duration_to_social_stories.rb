class AddDurationToSocialStories < ActiveRecord::Migration[8.1]
  def change
    add_column :social_stories, :duration_seconds, :integer
  end
end
