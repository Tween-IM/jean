# frozen_string_literal: true

class CreateSocialCommentLikes < ActiveRecord::Migration[8.1]
  def change
    create_table :social_comment_likes do |t|
      t.bigint :social_comment_id, null: false
      t.string :user_id, null: false

      t.timestamps
    end

    add_index :social_comment_likes, :social_comment_id
    add_index :social_comment_likes, :user_id
    add_index :social_comment_likes, [ :social_comment_id, :user_id ], unique: true
  end
end
