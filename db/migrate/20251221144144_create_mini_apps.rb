class CreateMiniApps < ActiveRecord::Migration[8.0]
  def change
    create_table :mini_apps do |t|
      t.string :app_id
      t.string :name
      t.text :description
      t.string :version
      t.integer :classification
      t.string :developer_name
      t.json :manifest
      t.integer :status

      t.timestamps
    end
    add_index :mini_apps, :app_id
  end
end
