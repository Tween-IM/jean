class AddInstallCountToMiniApps < ActiveRecord::Migration[8.1]
  def change
    add_column :mini_apps, :install_count, :integer, default: 0
  end
end
