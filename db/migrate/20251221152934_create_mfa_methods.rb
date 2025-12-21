class CreateMfaMethods < ActiveRecord::Migration[8.0]
  def change
    create_table :mfa_methods do |t|
      t.references :user, null: false, foreign_key: true
      t.string :method_type
      t.string :device_id
      t.text :public_key
      t.boolean :enabled

      t.timestamps
    end
  end
end
