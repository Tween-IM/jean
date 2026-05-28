class CreateSocialReports < ActiveRecord::Migration[8.1]
  def change
    create_table :social_reports do |t|
      t.references :social_video, null: false, foreign_key: true
      t.string :reporter_user_id, null: false
      t.string :reason, null: false
      t.text :details
      t.string :status, null: false, default: "open"
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :social_reports, [ :social_video_id, :reporter_user_id ], unique: true
    add_index :social_reports, :status
  end
end
