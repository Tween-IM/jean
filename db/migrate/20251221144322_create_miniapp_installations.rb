class CreateMiniappInstallations < ActiveRecord::Migration[8.0]
  def change
    create_table :miniapp_installations do |t|
      t.references :user, null: false, foreign_key: true
      t.references :miniapp, null: false, foreign_key: true
      t.string :version
      t.integer :status
      t.datetime :installed_at
      t.datetime :last_used_at

      t.timestamps
    end
  end
end
