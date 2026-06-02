class AddHlsTranscodeFieldsToSocialPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :social_posts, :transcode_status, :string, default: "pending"
    add_column :social_posts, :transcode_error, :text
    add_column :social_posts, :hls_master_url, :string
  end
end
