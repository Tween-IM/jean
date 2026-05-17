class AddReviewFieldsToMiniApps < ActiveRecord::Migration[8.1]
  def change
    add_column :mini_apps, :submitted_at, :datetime
    add_column :mini_apps, :reviewer_id, :integer
    add_column :mini_apps, :rejection_reason, :text
    add_column :mini_apps, :reviewed_at, :datetime
  end
end
