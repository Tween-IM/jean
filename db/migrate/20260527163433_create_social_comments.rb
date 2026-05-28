class CreateSocialComments < ActiveRecord::Migration[8.1]
  def change
    create_table :social_comments do |t|
      t.references :social_video, null: false, foreign_key: true
      t.references :parent_comment, foreign_key: { to_table: :social_comments }
      t.string :author_user_id, null: false
      t.text :body, null: false
      t.string :status, null: false, default: "active"

      t.timestamps
    end

    add_index :social_comments, [ :social_video_id, :created_at ]
    add_index :social_comments, :author_user_id
  end
end
