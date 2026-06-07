# frozen_string_literal: true

class CreateNotifications < ActiveRecord::Migration[8.0]
  def change
    create_table :notifications, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :user_id, null: false, comment: "Recipient matrix_user_id"
      t.string :actor_id, comment: "Actor matrix_user_id (null for system)"
      t.string :notification_type, null: false, comment: "like, comment, follow, mention, payment, system"
      t.string :source, null: false, default: "social", comment: "social, matrix, tweenpay, system"
      t.string :target_type, comment: "post, comment, creator, room, payment"
      t.string :target_id
      t.string :title
      t.text :body
      t.jsonb :metadata, default: {}
      t.datetime :read_at
      t.timestamps
    end

    add_index :notifications, [ :user_id, :read_at ], name: "index_notifications_on_user_id_and_read_at"
    add_index :notifications, [ :user_id, :created_at ], name: "index_notifications_on_user_id_and_created_at"
    add_index :notifications, [ :source, :user_id ], name: "index_notifications_on_source_and_user_id"
    add_index :notifications, [ :notification_type, :user_id ], name: "index_notifications_on_type_and_user_id"
  end
end
