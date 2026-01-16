# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_01_16_173558) do
  create_table "authorization_approvals", force: :cascade do |t|
    t.string "approval_method"
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.string "miniapp_id"
    t.string "scope"
    t.datetime "updated_at", null: false
    t.string "user_id"
    t.index ["miniapp_id"], name: "index_authorization_approvals_on_miniapp_id"
    t.index ["user_id"], name: "index_authorization_approvals_on_user_id"
  end

  create_table "mfa_methods", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "device_id"
    t.boolean "enabled"
    t.string "method_type"
    t.text "public_key"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_mfa_methods_on_user_id"
  end

  create_table "mini_app_appeals", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "miniapp_id"
    t.text "reason"
    t.string "status"
    t.text "supporting_info"
    t.datetime "updated_at", null: false
    t.string "user_id"
    t.index ["miniapp_id"], name: "index_mini_app_appeals_on_miniapp_id"
    t.index ["user_id"], name: "index_mini_app_appeals_on_user_id"
  end

  create_table "mini_app_automated_checks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "csp_valid"
    t.boolean "dependency_scan_passed"
    t.boolean "https_only"
    t.string "miniapp_id"
    t.boolean "no_credentials"
    t.boolean "no_obfuscation"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["miniapp_id"], name: "index_mini_app_automated_checks_on_miniapp_id"
  end

  create_table "mini_apps", force: :cascade do |t|
    t.string "app_id"
    t.integer "classification"
    t.string "client_type", default: "public", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "developer_name"
    t.integer "install_count", default: 0
    t.json "manifest"
    t.string "name"
    t.integer "status"
    t.datetime "updated_at", null: false
    t.string "version"
    t.index ["app_id"], name: "index_mini_apps_on_app_id"
    t.index ["client_type"], name: "index_mini_apps_on_client_type"
  end

  create_table "miniapp_installations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "installed_at"
    t.datetime "last_used_at"
    t.integer "mini_app_id", null: false
    t.integer "status"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.string "version"
    t.index ["mini_app_id"], name: "index_miniapp_installations_on_mini_app_id"
    t.index ["user_id"], name: "index_miniapp_installations_on_user_id"
  end

  create_table "oauth_access_grants", force: :cascade do |t|
    t.integer "application_id", null: false
    t.datetime "created_at", null: false
    t.integer "expires_in", null: false
    t.text "redirect_uri", null: false
    t.integer "resource_owner_id", null: false
    t.datetime "revoked_at"
    t.string "scopes", default: "", null: false
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_grants_on_application_id"
    t.index ["resource_owner_id"], name: "index_oauth_access_grants_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_grants_on_token", unique: true
  end

  create_table "oauth_access_tokens", force: :cascade do |t|
    t.integer "application_id", null: false
    t.datetime "created_at", null: false
    t.integer "expires_in"
    t.string "previous_refresh_token", default: "", null: false
    t.string "refresh_token"
    t.integer "resource_owner_id"
    t.datetime "revoked_at"
    t.string "scopes"
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_tokens_on_application_id"
    t.index ["refresh_token"], name: "index_oauth_access_tokens_on_refresh_token", unique: true
    t.index ["resource_owner_id"], name: "index_oauth_access_tokens_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_tokens_on_token", unique: true
  end

  create_table "oauth_applications", force: :cascade do |t|
    t.boolean "confidential", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.text "redirect_uri", null: false
    t.string "scopes", default: "", null: false
    t.string "secret", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["uid"], name: "index_oauth_applications_on_uid", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "data"
    t.string "session_id", null: false
    t.datetime "updated_at", null: false
    t.index ["session_id"], name: "index_sessions_on_session_id", unique: true
    t.index ["updated_at"], name: "index_sessions_on_updated_at"
  end

  create_table "storage_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "key"
    t.string "miniapp_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.text "value"
    t.index ["user_id"], name: "index_storage_entries_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "mas_user_id"
    t.string "matrix_homeserver"
    t.string "matrix_user_id"
    t.string "matrix_username"
    t.integer "status"
    t.datetime "updated_at", null: false
    t.string "wallet_id"
    t.index ["mas_user_id"], name: "index_users_on_mas_user_id", unique: true
    t.index ["matrix_user_id"], name: "index_users_on_matrix_user_id"
  end

  add_foreign_key "mfa_methods", "users"
  add_foreign_key "miniapp_installations", "mini_apps"
  add_foreign_key "miniapp_installations", "users"
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "storage_entries", "users"
end
