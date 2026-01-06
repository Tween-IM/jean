class CreateMiniAppAutomatedChecks < ActiveRecord::Migration[8.1]
  def change
    create_table :mini_app_automated_checks do |t|
      t.string :miniapp_id
      t.string :status
      t.boolean :csp_valid
      t.boolean :https_only
      t.boolean :no_credentials
      t.boolean :no_obfuscation
      t.boolean :dependency_scan_passed

      t.timestamps
    end
    add_index :mini_app_automated_checks, :miniapp_id
  end
end
