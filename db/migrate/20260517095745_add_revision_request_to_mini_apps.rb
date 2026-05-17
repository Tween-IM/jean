class AddRevisionRequestToMiniApps < ActiveRecord::Migration[8.1]
  def change
    add_column :mini_apps, :revision_request, :text
    add_column :mini_apps, :revision_requested_at, :datetime
  end
end
