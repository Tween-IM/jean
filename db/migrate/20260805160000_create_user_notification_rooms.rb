class CreateUserNotificationRooms < ActiveRecord::Migration[8.1]
  def change
    create_table :user_notification_rooms do |t|
      t.string :user_id, null: false
      t.string :matrix_room_id, null: false

      t.timestamps
    end

    add_index :user_notification_rooms, :user_id, unique: true
  end
end
