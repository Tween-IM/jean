class CreateSocialFollows < ActiveRecord::Migration[8.1]
  def change
    create_table :social_follows do |t|
      t.string :follower_user_id, null: false
      t.string :creator_user_id, null: false
      t.string :status, null: false, default: "active"

      t.timestamps
    end

    add_index :social_follows, [ :follower_user_id, :creator_user_id ], unique: true
    add_index :social_follows, :creator_user_id
  end
end
