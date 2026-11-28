# frozen_string_literal: true

class AddDeveloperUserIdToMiniApps < ActiveRecord::Migration[8.0]
  def change
    add_column :mini_apps, :developer_user_id, :string
    add_index :mini_apps, :developer_user_id
  end
end
