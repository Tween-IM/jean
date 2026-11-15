class CreateAdminOauthGrants < ActiveRecord::Migration[8.1]
  def change
    create_table :admin_oauth_grants do |t|
      t.references :user, null: false, foreign_key: true
      t.string :session_digest, null: false
      t.string :subject, null: false
      t.string :issuer, null: false
      t.string :client_id, null: false
      t.text :encrypted_credentials, null: false
      t.text :scope, null: false
      t.datetime :expires_at, null: false
      t.datetime :session_expires_at, null: false
      t.timestamps
    end
    add_index :admin_oauth_grants, :session_digest, unique: true
    add_index :admin_oauth_grants, :session_expires_at
  end
end
