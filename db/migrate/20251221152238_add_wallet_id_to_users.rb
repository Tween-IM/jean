class AddWalletIdToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :wallet_id, :string
  end
end
