class AddPlatformRoleToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :platform_role, :string, default: "none", null: false
    add_column :users, :admin_mfa_enabled, :boolean, default: false, null: false
    add_column :users, :admin_mfa_secret, :string
  end
end
