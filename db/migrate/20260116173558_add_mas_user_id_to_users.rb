class AddMasUserIdToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :mas_user_id, :string
    add_index :users, :mas_user_id, unique: true
  end
end
