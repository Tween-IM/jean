class CreateMiniAppAppeals < ActiveRecord::Migration[8.1]
  def change
    create_table :mini_app_appeals do |t|
      t.string :miniapp_id
      t.string :user_id
      t.text :reason
      t.text :supporting_info
      t.string :status

      t.timestamps
    end
    add_index :mini_app_appeals, :miniapp_id
    add_index :mini_app_appeals, :user_id
  end
end
