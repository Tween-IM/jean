class CreateSocialShares < ActiveRecord::Migration[8.1]
  def change
    create_table :social_shares do |t|
      t.references :social_video, null: false, foreign_key: true
      t.string :user_id, null: false
      t.string :target, null: false, default: "link"
      t.string :room_id
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :social_shares, [ :social_video_id, :created_at ]
    add_index :social_shares, [ :user_id, :created_at ]
  end
end
