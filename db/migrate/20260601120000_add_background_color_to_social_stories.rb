class AddBackgroundColorToSocialStories < ActiveRecord::Migration[8.1]
  def change
    add_column :social_stories, :background_color, :string
  end
end
