class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :matrix_user_id
      t.string :matrix_username
      t.string :matrix_homeserver
      t.integer :status

      t.timestamps
    end
    add_index :users, :matrix_user_id
  end
end
