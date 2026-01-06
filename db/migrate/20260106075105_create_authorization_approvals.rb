class CreateAuthorizationApprovals < ActiveRecord::Migration[8.1]
  def change
    create_table :authorization_approvals do |t|
      t.string :user_id
      t.string :miniapp_id
      t.string :scope
      t.datetime :approved_at
      t.string :approval_method

      t.timestamps
    end
    add_index :authorization_approvals, :user_id
    add_index :authorization_approvals, :miniapp_id
  end
end
