class CreateAdminAuditEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :admin_audit_events do |t|
      t.string :actor_matrix_id, null: false
      t.string :action, null: false
      t.string :target
      t.string :request_id
      t.string :outcome, null: false, default: "success"
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end
    add_index :admin_audit_events, :created_at
    add_index :admin_audit_events, :actor_matrix_id
    add_index :admin_audit_events, :request_id
  end
end
