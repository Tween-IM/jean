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

ActiveRecord::Schema[8.1].define(version: 2026_06_02_175453) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

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

  create_table "commerce_cart_items", force: :cascade do |t|
    t.bigint "commerce_cart_id", null: false
    t.bigint "commerce_sku_id", null: false
    t.datetime "created_at", null: false
    t.string "currency", null: false
    t.integer "line_total_cents", null: false
    t.integer "quantity", null: false
    t.integer "unit_price_cents", null: false
    t.datetime "updated_at", null: false
    t.index ["commerce_cart_id", "commerce_sku_id"], name: "index_commerce_cart_items_unique_sku", unique: true
    t.index ["commerce_cart_id"], name: "index_commerce_cart_items_on_commerce_cart_id"
    t.index ["commerce_sku_id"], name: "index_commerce_cart_items_on_commerce_sku_id"
  end

  create_table "commerce_carts", force: :cascade do |t|
    t.string "buyer_user_id", null: false
    t.string "cart_id", null: false
    t.bigint "commerce_merchant_id", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "NGN", null: false
    t.integer "discount_cents", default: 0, null: false
    t.integer "shipping_cents", default: 0, null: false
    t.string "status", default: "active", null: false
    t.integer "subtotal_cents", default: 0, null: false
    t.integer "tax_cents", default: 0, null: false
    t.integer "total_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["buyer_user_id", "status"], name: "index_commerce_carts_on_buyer_user_id_and_status"
    t.index ["cart_id"], name: "index_commerce_carts_on_cart_id", unique: true
    t.index ["commerce_merchant_id"], name: "index_commerce_carts_on_commerce_merchant_id"
  end

  create_table "commerce_checkouts", force: :cascade do |t|
    t.string "buyer_user_id", null: false
    t.string "checkout_id", null: false
    t.bigint "commerce_cart_id", null: false
    t.bigint "commerce_merchant_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "idempotency_key"
    t.jsonb "metadata", default: {}, null: false
    t.string "order_id"
    t.string "payment_id"
    t.string "shipping_address_line1"
    t.string "shipping_address_line2"
    t.string "shipping_city"
    t.string "shipping_country", default: "NG"
    t.string "shipping_phone"
    t.string "shipping_postal_code"
    t.string "shipping_state"
    t.string "status", default: "created", null: false
    t.datetime "updated_at", null: false
    t.index ["buyer_user_id", "idempotency_key"], name: "index_commerce_checkouts_on_buyer_user_id_and_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["buyer_user_id", "status"], name: "index_commerce_checkouts_on_buyer_user_id_and_status"
    t.index ["checkout_id"], name: "index_commerce_checkouts_on_checkout_id", unique: true
    t.index ["commerce_cart_id"], name: "index_commerce_checkouts_on_commerce_cart_id"
    t.index ["commerce_merchant_id"], name: "index_commerce_checkouts_on_commerce_merchant_id"
    t.index ["payment_id"], name: "index_commerce_checkouts_on_payment_id"
  end

  create_table "commerce_merchants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "display_name", null: false
    t.string "merchant_id", null: false
    t.string "miniapp_id", null: false
    t.string "owner_user_id"
    t.string "status", default: "pending_review", null: false
    t.datetime "updated_at", null: false
    t.string "wallet_id", null: false
    t.string "webhook_url"
    t.index ["merchant_id"], name: "index_commerce_merchants_on_merchant_id", unique: true
    t.index ["miniapp_id"], name: "index_commerce_merchants_on_miniapp_id"
    t.index ["status"], name: "index_commerce_merchants_on_status"
  end

  create_table "commerce_order_items", force: :cascade do |t|
    t.bigint "commerce_order_id", null: false
    t.datetime "created_at", null: false
    t.string "currency", null: false
    t.integer "line_total_cents", null: false
    t.string "product_id", null: false
    t.integer "quantity", null: false
    t.string "sku_id", null: false
    t.string "title", null: false
    t.integer "unit_price_cents", null: false
    t.datetime "updated_at", null: false
    t.index ["commerce_order_id"], name: "index_commerce_order_items_on_commerce_order_id"
  end

  create_table "commerce_orders", force: :cascade do |t|
    t.string "buyer_user_id", null: false
    t.bigint "commerce_merchant_id", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "NGN", null: false
    t.integer "discount_cents", default: 0, null: false
    t.string "fulfillment_status", default: "unfulfilled", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "order_id", null: false
    t.string "payment_id", null: false
    t.string "shipping_address_line1"
    t.string "shipping_address_line2"
    t.integer "shipping_cents", default: 0, null: false
    t.string "shipping_city"
    t.string "shipping_country", default: "NG"
    t.string "shipping_phone"
    t.string "shipping_postal_code"
    t.string "shipping_state"
    t.string "status", default: "pending_payment", null: false
    t.integer "subtotal_cents", default: 0, null: false
    t.integer "tax_cents", default: 0, null: false
    t.integer "total_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["buyer_user_id", "status"], name: "index_commerce_orders_on_buyer_user_id_and_status"
    t.index ["commerce_merchant_id"], name: "index_commerce_orders_on_commerce_merchant_id"
    t.index ["order_id"], name: "index_commerce_orders_on_order_id", unique: true
    t.index ["payment_id"], name: "index_commerce_orders_on_payment_id"
  end

  create_table "commerce_products", force: :cascade do |t|
    t.bigint "commerce_merchant_id", null: false
    t.bigint "commerce_storefront_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.json "media_urls", default: [], null: false
    t.string "product_id", null: false
    t.string "status", default: "draft", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["commerce_merchant_id", "status"], name: "index_commerce_products_on_commerce_merchant_id_and_status"
    t.index ["commerce_merchant_id"], name: "index_commerce_products_on_commerce_merchant_id"
    t.index ["commerce_storefront_id"], name: "index_commerce_products_on_commerce_storefront_id"
    t.index ["product_id"], name: "index_commerce_products_on_product_id", unique: true
  end

  create_table "commerce_skus", force: :cascade do |t|
    t.bigint "commerce_product_id", null: false
    t.datetime "created_at", null: false
    t.string "currency", null: false
    t.string "inventory_status", default: "in_stock", null: false
    t.integer "price_cents", null: false
    t.json "properties", default: {}, null: false
    t.integer "quantity_available"
    t.string "sku_id", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["commerce_product_id", "inventory_status"], name: "idx_on_commerce_product_id_inventory_status_95970cbd24"
    t.index ["commerce_product_id"], name: "index_commerce_skus_on_commerce_product_id"
    t.index ["sku_id"], name: "index_commerce_skus_on_sku_id", unique: true
  end

  create_table "commerce_storefronts", force: :cascade do |t|
    t.bigint "commerce_merchant_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "display_name", null: false
    t.string "slug", null: false
    t.string "status", default: "draft", null: false
    t.string "storefront_id", null: false
    t.datetime "updated_at", null: false
    t.index ["commerce_merchant_id", "slug"], name: "index_commerce_storefronts_on_commerce_merchant_id_and_slug", unique: true
    t.index ["commerce_merchant_id"], name: "index_commerce_storefronts_on_commerce_merchant_id"
    t.index ["storefront_id"], name: "index_commerce_storefronts_on_storefront_id", unique: true
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
    t.text "rejection_reason"
    t.datetime "reviewed_at"
    t.integer "reviewer_id"
    t.text "revision_request"
    t.datetime "revision_requested_at"
    t.integer "status"
    t.datetime "submitted_at"
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

  create_table "social_bookmarks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "social_post_id", null: false
    t.datetime "updated_at", null: false
    t.string "user_id", null: false
    t.index ["social_post_id", "user_id"], name: "index_social_bookmarks_on_social_post_id_and_user_id", unique: true
    t.index ["social_post_id"], name: "index_social_bookmarks_on_social_post_id"
    t.index ["user_id", "created_at"], name: "index_social_bookmarks_on_user_id_and_created_at"
  end

  create_table "social_comment_likes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "social_comment_id", null: false
    t.datetime "updated_at", null: false
    t.string "user_id", null: false
    t.index ["social_comment_id", "user_id"], name: "index_social_comment_likes_on_social_comment_id_and_user_id", unique: true
    t.index ["social_comment_id"], name: "index_social_comment_likes_on_social_comment_id"
    t.index ["user_id"], name: "index_social_comment_likes_on_user_id"
  end

  create_table "social_comments", force: :cascade do |t|
    t.string "author_user_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.bigint "parent_comment_id"
    t.bigint "social_post_id", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["author_user_id"], name: "index_social_comments_on_author_user_id"
    t.index ["parent_comment_id"], name: "index_social_comments_on_parent_comment_id"
    t.index ["social_post_id", "created_at"], name: "index_social_comments_on_social_post_id_and_created_at"
    t.index ["social_post_id"], name: "index_social_comments_on_social_post_id"
  end

  create_table "social_creator_profiles", force: :cascade do |t|
    t.string "avatar_url"
    t.text "bio"
    t.string "commerce_storefront_id"
    t.datetime "created_at", null: false
    t.string "display_name"
    t.integer "follower_count", default: 0, null: false
    t.integer "following_count", default: 0, null: false
    t.string "handle", null: false
    t.integer "post_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "user_id", null: false
    t.boolean "verified", default: false, null: false
    t.index ["handle"], name: "index_social_creator_profiles_on_handle", unique: true
    t.index ["user_id"], name: "index_social_creator_profiles_on_user_id", unique: true
  end

  create_table "social_follows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "creator_user_id", null: false
    t.string "follower_user_id", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_user_id"], name: "index_social_follows_on_creator_user_id"
    t.index ["follower_user_id", "creator_user_id"], name: "index_social_follows_on_follower_user_id_and_creator_user_id", unique: true
  end

  create_table "social_likes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "social_post_id", null: false
    t.datetime "updated_at", null: false
    t.string "user_id", null: false
    t.index ["social_post_id", "user_id"], name: "index_social_likes_on_social_post_id_and_user_id", unique: true
    t.index ["social_post_id"], name: "index_social_likes_on_social_post_id"
  end

  create_table "social_posts", force: :cascade do |t|
    t.text "caption"
    t.integer "comment_count", default: 0, null: false
    t.json "commerce_refs", default: [], null: false
    t.string "content_type", default: "video", null: false
    t.datetime "created_at", null: false
    t.string "creator_user_id", null: false
    t.datetime "deleted_at"
    t.integer "duration_seconds"
    t.integer "height"
    t.string "hls_master_url"
    t.integer "like_count", default: 0, null: false
    t.string "media_upload_id", null: false
    t.string "moderation_status", default: "pending", null: false
    t.string "playback_url"
    t.string "post_id", null: false
    t.datetime "published_at"
    t.integer "share_count", default: 0, null: false
    t.string "status", default: "processing", null: false
    t.string "thumbnail_url"
    t.text "transcode_error"
    t.string "transcode_status", default: "pending"
    t.datetime "updated_at", null: false
    t.json "variants", default: [], null: false
    t.integer "view_count", default: 0, null: false
    t.string "visibility", default: "public", null: false
    t.integer "width"
    t.index ["content_type"], name: "index_social_posts_on_content_type"
    t.index ["creator_user_id", "created_at"], name: "index_social_posts_on_creator_user_id_and_created_at"
    t.index ["post_id"], name: "index_social_posts_on_post_id", unique: true
    t.index ["status", "moderation_status", "visibility"], name: "index_social_videos_feed_eligibility"
  end

  create_table "social_reports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "details"
    t.jsonb "metadata", default: {}, null: false
    t.string "reason", null: false
    t.string "reporter_user_id", null: false
    t.bigint "social_post_id", null: false
    t.string "status", default: "open", null: false
    t.datetime "updated_at", null: false
    t.index ["social_post_id", "reporter_user_id"], name: "index_social_reports_on_social_post_id_and_reporter_user_id", unique: true
    t.index ["social_post_id"], name: "index_social_reports_on_social_post_id"
    t.index ["status"], name: "index_social_reports_on_status"
  end

  create_table "social_shares", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "room_id"
    t.bigint "social_post_id", null: false
    t.string "target", default: "link", null: false
    t.datetime "updated_at", null: false
    t.string "user_id", null: false
    t.index ["social_post_id", "created_at"], name: "index_social_shares_on_social_post_id_and_created_at"
    t.index ["social_post_id"], name: "index_social_shares_on_social_post_id"
    t.index ["user_id", "created_at"], name: "index_social_shares_on_user_id_and_created_at"
  end

  create_table "social_stories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "background_color"
    t.text "caption"
    t.datetime "created_at", null: false
    t.string "creator_user_id", null: false
    t.integer "duration_seconds"
    t.datetime "expires_at", null: false
    t.string "media_type", default: "image", null: false
    t.string "media_url"
    t.string "status", default: "active", null: false
    t.string "story_id", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_user_id", "status", "expires_at"], name: "idx_social_stories_creator_active"
    t.index ["creator_user_id"], name: "index_social_stories_on_creator_user_id"
    t.index ["status", "expires_at"], name: "index_social_stories_on_status_and_expires_at"
    t.index ["story_id"], name: "index_social_stories_on_story_id", unique: true
  end

  create_table "social_story_views", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "social_story_id", null: false
    t.datetime "updated_at", null: false
    t.datetime "viewed_at", null: false
    t.string "viewer_user_id", null: false
    t.index ["social_story_id", "viewer_user_id"], name: "idx_social_story_views_unique", unique: true
    t.index ["social_story_id"], name: "index_social_story_views_on_social_story_id"
    t.index ["viewer_user_id"], name: "index_social_story_views_on_viewer_user_id"
  end

  create_table "social_views", force: :cascade do |t|
    t.boolean "completed", default: false, null: false
    t.datetime "created_at", null: false
    t.string "session_id", null: false
    t.bigint "social_post_id", null: false
    t.datetime "updated_at", null: false
    t.datetime "viewed_at", null: false
    t.string "viewer_user_id", null: false
    t.integer "watched_ms", default: 0, null: false
    t.index ["social_post_id", "viewer_user_id", "session_id"], name: "index_social_views_once_per_session", unique: true
    t.index ["social_post_id"], name: "index_social_views_on_social_post_id"
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
    t.boolean "admin_mfa_enabled", default: false, null: false
    t.string "admin_mfa_secret"
    t.datetime "created_at", null: false
    t.string "mas_user_id"
    t.string "matrix_homeserver"
    t.string "matrix_user_id"
    t.string "matrix_username"
    t.string "platform_role", default: "none", null: false
    t.integer "status"
    t.datetime "updated_at", null: false
    t.string "wallet_id"
    t.index ["mas_user_id"], name: "index_users_on_mas_user_id", unique: true
    t.index ["matrix_user_id"], name: "index_users_on_matrix_user_id"
  end

  create_table "webhook_deliveries", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.string "event_id", null: false
    t.string "event_type", null: false
    t.text "last_error"
    t.datetime "next_attempt_at"
    t.jsonb "payload", default: {}, null: false
    t.integer "response_status"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.string "webhook_url", null: false
    t.index ["event_id"], name: "index_webhook_deliveries_on_event_id", unique: true
    t.index ["event_type"], name: "index_webhook_deliveries_on_event_type"
    t.index ["status", "next_attempt_at"], name: "index_webhook_deliveries_on_status_and_next_attempt_at"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "commerce_cart_items", "commerce_carts"
  add_foreign_key "commerce_cart_items", "commerce_skus"
  add_foreign_key "commerce_carts", "commerce_merchants"
  add_foreign_key "commerce_checkouts", "commerce_carts"
  add_foreign_key "commerce_checkouts", "commerce_merchants"
  add_foreign_key "commerce_order_items", "commerce_orders"
  add_foreign_key "commerce_orders", "commerce_merchants"
  add_foreign_key "commerce_products", "commerce_merchants"
  add_foreign_key "commerce_products", "commerce_storefronts"
  add_foreign_key "commerce_skus", "commerce_products"
  add_foreign_key "commerce_storefronts", "commerce_merchants"
  add_foreign_key "mfa_methods", "users"
  add_foreign_key "miniapp_installations", "mini_apps"
  add_foreign_key "miniapp_installations", "users"
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "social_bookmarks", "social_posts"
  add_foreign_key "social_comments", "social_comments", column: "parent_comment_id"
  add_foreign_key "social_comments", "social_posts"
  add_foreign_key "social_likes", "social_posts"
  add_foreign_key "social_reports", "social_posts"
  add_foreign_key "social_shares", "social_posts"
  add_foreign_key "social_story_views", "social_stories"
  add_foreign_key "social_views", "social_posts"
  add_foreign_key "storage_entries", "users"
end
