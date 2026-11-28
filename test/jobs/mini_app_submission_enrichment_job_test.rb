# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class MiniAppSubmissionEnrichmentJobTest < ActiveJob::TestCase
  test "fills a URL-only submission from the website" do
    app = MiniApp.create!(
      app_id: "ma_enrichme",
      name: "Example",
      description: "",
      version: "1.0.0",
      classification: :community,
      status: :pending_review,
      manifest: {
        scopes: [ "public" ],
        permissions: [],
        category: "utilities",
        entry_url: "https://example.com",
        enrichment: {
          "pending" => true,
          "fill_name" => true,
          "fill_description" => true,
          "fill_category" => true,
          "fill_icon" => true,
          "fill_screenshots" => true
        }
      }
    )

    preview = Object.new
    def preview.call(_url)
      {
        name: "Lagos Rent Calculator",
        description: "Work out agency, legal and caution fees.",
        category: "finance",
        icon_url: "https://example.com/icon.png",
        screenshots: [ "https://example.com/shot.png" ],
        header_image: "https://example.com/cover.png"
      }
    end

    MiniAppWebsitePreview.stub(:new, -> { preview }) do
      MiniAppSubmissionEnrichmentJob.perform_now(app.id)
    end

    app.reload
    assert_equal "Lagos Rent Calculator", app.name
    assert_equal "Work out agency, legal and caution fees.", app.description
    assert_equal "finance", app.manifest["category"]
    assert_equal "https://example.com/icon.png", app.manifest["icon_url"]
    assert_equal [ "https://example.com/shot.png" ], app.manifest["screenshots"]
    assert_equal "https://example.com/cover.png", app.manifest["header_image"]
    refute app.manifest.dig("enrichment", "pending")
  end

  test "stops waiting when the site cannot be read" do
    app = MiniApp.create!(
      app_id: "ma_unreadable",
      name: "Example",
      description: "",
      version: "1.0.0",
      classification: :community,
      status: :pending_review,
      manifest: {
        scopes: [ "public" ],
        permissions: [],
        category: "utilities",
        entry_url: "https://example.com",
        enrichment: {
          "pending" => true,
          "fill_name" => true,
          "fill_icon" => true
        }
      }
    )

    preview = Object.new
    def preview.call(_url)
      raise PublicWebsiteFetch::Unavailable
    end

    MiniAppWebsitePreview.stub(:new, -> { preview }) do
      MiniAppSubmissionEnrichmentJob.perform_now(app.id)
    end

    app.reload
    refute app.manifest.dig("enrichment", "pending")
    assert app.manifest.dig("enrichment", "failed")
  end
end
