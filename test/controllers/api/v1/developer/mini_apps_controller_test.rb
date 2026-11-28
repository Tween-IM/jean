# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class Api::V1::Developer::MiniAppsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      matrix_user_id: "@publisher:tween.example",
      matrix_username: "publisher:tween.example",
      matrix_homeserver: "tween.example"
    )
    @other = User.create!(
      matrix_user_id: "@other:tween.example",
      matrix_username: "other:tween.example",
      matrix_homeserver: "tween.example"
    )
    @token = TepTokenService.encode(
      { user_id: @user.matrix_user_id, miniapp_id: "ma_tweensocial" },
      scopes: [ "user:read" ]
    )
    @headers = { "Authorization" => "Bearer #{@token}" }
  end

  test "publishes a website submission into the review queue" do
    post "/api/v1/developer/mini_apps", params: {
      name: "Lagos Rent Calculator",
      description: "Work out agency, legal and caution fees before you pay.",
      entry_url: "https://example.com/rent",
      icon_url: "https://example.com/icon.png",
      category: "utilities",
      developer_name: "Publisher Studio",
      permissions: [ "user:read", "storage:read" ],
      screenshots: [ "https://example.com/shot.png" ]
    }, headers: @headers, as: :json

    assert_response :created
    body = JSON.parse(response.body).fetch("app")
    assert_equal "pending_review", body["status"]

    app = MiniApp.find_by!(app_id: body["miniapp_id"])
    assert_equal "Publisher Studio", app.developer_name
    assert_equal @user.matrix_user_id, app.developer_user_id
    assert_equal "community", app.classification
    assert_equal "pending_review", app.status
    assert_equal "https://example.com/rent", app.manifest["entry_url"]
    assert_equal "utilities", app.manifest["category"]
    assert_equal [ "user:read", "storage:read" ], app.manifest["permissions"]
    assert_equal [ "public", "user:read", "storage:read" ], app.manifest["scopes"]
    assert_equal [ "https://example.com/rent" ], app.manifest["redirect_uris"]
    assert app.submitted_at.present?
  end

  test "creates a submission from just a URL using website metadata" do
    preview = Object.new
    def preview.call(_url)
      {
        name: "Lagos Rent Calculator",
        description: "Work out agency, legal and caution fees.",
        icon_url: "https://example.com/icon.png",
        screenshots: [ "https://example.com/shot.png" ],
        header_image: "https://example.com/cover.png",
        category: "utilities"
      }
    end

    MiniAppWebsitePreview.stub(:new, -> { preview }) do
      post "/api/v1/developer/mini_apps", params: {
        entry_url: "https://example.com/rent"
      }, headers: @headers, as: :json
    end

    assert_response :created
    body = JSON.parse(response.body).fetch("app")
    assert_equal "Lagos Rent Calculator", body["name"]
    assert_equal "utilities", body["category"]
    assert_equal "https://example.com/icon.png", body["icon_url"]
    assert_equal [ "https://example.com/shot.png" ], body["screenshots"]

    app = MiniApp.find_by!(app_id: body["miniapp_id"])
    assert_equal "Work out agency, legal and caution fees.", app.description
    assert_equal [], app.manifest["permissions"]
    assert_equal [ "public" ], app.manifest["scopes"]
    refute app.manifest.dig("enrichment", "pending")
  end

  test "creates a provisional app and queues enrichment when the site is unreadable" do
    preview = Object.new
    def preview.call(_url)
      raise PublicWebsiteFetch::Unavailable
    end

    assert_enqueued_with(job: MiniAppSubmissionEnrichmentJob) do
      MiniAppWebsitePreview.stub(:new, -> { preview }) do
        post "/api/v1/developer/mini_apps", params: {
          entry_url: "https://example.com/rent"
        }, headers: @headers, as: :json
      end
    end

    assert_response :created
    app = MiniApp.find_by!(app_id: JSON.parse(response.body).dig("app", "miniapp_id"))
    assert_equal "Example", app.name
    assert_equal "utilities", app.manifest["category"]
    assert app.manifest.dig("enrichment", "pending")
  end

  test "lists only the current developer's apps" do
    MiniApp.create!(
      app_id: "ma_mine",
      name: "Mine",
      description: "Mine",
      version: "1.0.0",
      classification: :community,
      status: :pending_review,
      developer_user_id: @user.matrix_user_id,
      manifest: { scopes: [ "public" ], entry_url: "https://example.com/mine" }
    )
    MiniApp.create!(
      app_id: "ma_theirs",
      name: "Theirs",
      description: "Theirs",
      version: "1.0.0",
      classification: :community,
      status: :pending_review,
      developer_user_id: @other.matrix_user_id,
      manifest: { scopes: [ "public" ], entry_url: "https://example.com/theirs" }
    )

    get "/api/v1/developer/mini_apps", headers: @headers

    assert_response :success
    ids = JSON.parse(response.body).fetch("apps").map { |app| app["miniapp_id"] }
    assert_equal [ "ma_mine" ], ids & [ "ma_mine", "ma_theirs" ]
  end

  test "resubmits changes requested apps and clears the old request" do
    app = create_submission
    app.request_changes!(reviewer_id: @other.id, reason: "Add a privacy policy link.")

    patch "/api/v1/developer/mini_apps/#{app.app_id}", params: {
      description: "Updated description with the privacy policy link."
    }, headers: @headers, as: :json

    assert_response :success
    app.reload
    assert_equal "pending_review", app.status
    assert_nil app.revision_request
    assert app.submitted_at.present?
  end

  test "does not let another user edit a submission" do
    app = create_submission
    other_token = TepTokenService.encode(
      { user_id: @other.matrix_user_id, miniapp_id: "ma_tweensocial" },
      scopes: [ "user:read" ]
    )

    patch "/api/v1/developer/mini_apps/#{app.app_id}", params: {
      name: "Hijacked"
    }, headers: { "Authorization" => "Bearer #{other_token}" }, as: :json

    assert_response :not_found
    assert_equal "Test App", app.reload.name
  end

  test "rejects non-HTTPS launches and unknown categories" do
    post "/api/v1/developer/mini_apps", params: {
      name: "Bad link",
      description: "This should not be accepted.",
      entry_url: "http://example.com/app",
      category: "utilities"
    }, headers: @headers, as: :json
    assert_response :unprocessable_entity

    post "/api/v1/developer/mini_apps", params: {
      name: "Bad category",
      description: "This should not be accepted.",
      entry_url: "https://example.com/app",
      category: "betting"
    }, headers: @headers, as: :json
    assert_response :unprocessable_entity
  end

  test "requires a TEP token" do
    get "/api/v1/developer/mini_apps"
    assert_response :unauthorized
  end

  test "rejects tokens minted for third-party mini apps" do
    token = TepTokenService.encode(
      { user_id: @user.matrix_user_id, miniapp_id: "ma_thirdparty" },
      scopes: [ "user:read" ]
    )
    get "/api/v1/developer/mini_apps",
      headers: { "Authorization" => "Bearer #{token}" }

    assert_response :forbidden
  end

  test "admin approval makes a submission activatable" do
    app = create_submission
    reviewer = User.create!(
      matrix_user_id: "@reviewer:tween.example",
      matrix_username: "reviewer:tween.example",
      matrix_homeserver: "tween.example"
    )

    app.approve!(reviewer_id: reviewer.id)
    assert_equal "approved", app.reload.status

    app.activate!
    assert_equal "active", app.reload.status
  end

  private

  def create_submission
    MiniApp.create!(
      app_id: "ma_testapp",
      name: "Test App",
      description: "A test submission.",
      version: "1.0.0",
      classification: :community,
      status: :pending_review,
      developer_user_id: @user.matrix_user_id,
      submitted_at: Time.current,
      manifest: {
        scopes: [ "public", "user:read" ],
        permissions: [ "user:read" ],
        category: "utilities",
        entry_url: "https://example.com/app",
        icon_url: "https://example.com/icon.png",
        redirect_uris: [ "https://example.com/app" ],
        runtime: "website",
        developer: { name: "Publisher Studio" }
      }
    )
  end
end
