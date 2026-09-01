# frozen_string_literal: true

class CreateNotificationPreferences < ActiveRecord::Migration[8.0]
  def change
    create_table :notification_preferences, id: :uuid do |t|
      t.string :user_id, null: false, comment: "Matrix user ID"
      t.string :channel, null: false, comment: "in_app, push, email"
      t.string :notification_type, null: false, default: "all", comment: "all, social, commerce, payment, system"
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end

    add_index :notification_preferences, [:user_id, :channel, :notification_type],
              unique: true, name: "idx_notif_prefs_unique"
    add_index :notification_preferences, :user_id
  end
end
