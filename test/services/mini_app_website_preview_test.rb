# frozen_string_literal: true

require "test_helper"

class MiniAppWebsitePreviewTest < ActiveSupport::TestCase
  class FixtureFetcher
    def initialize(fixtures)
      @fixtures = fixtures
    end

    def get(url, accept:, max_bytes:)
      @fixtures.fetch(url.to_s) { raise PublicWebsiteFetch::Unavailable }
    end

    def public_destination?(url)
      url.hostname.end_with?(".example.com")
    end
  end

  test "reads manifest screenshots and resolves assets against the final document and manifest URLs" do
    page = response("https://app.example.com/product/index.html", <<~HTML)
      <title>Marketing title</title>
      <link rel="canonical" href="/information">
      <link rel="manifest" href="app.webmanifest">
      <meta property="og:image" content="cover.jpg">
    HTML
    manifest = response("https://assets.example.com/v2/app.webmanifest", <<~JSON)
      {"name":"Product","description":"A useful app","icons":[
        {"src":"tiny.png","sizes":"32x32"},{"src":"mask.png","sizes":"512x512","purpose":"maskable"},
        {"src":"icon.png","sizes":"192x192"}],
      "screenshots":[{"src":"shot.webp"},{"src":"shot.webp"},{"src":"https://private.test/x.png"}]}
    JSON
    result = preview({
      "https://app.example.com/start" => page,
      "https://app.example.com/product/app.webmanifest" => manifest
    })

    assert_equal "Product", result[:name]
    assert_equal "A useful app", result[:description]
    assert_equal "https://assets.example.com/v2/icon.png", result[:icon_url]
    assert_equal ["https://assets.example.com/v2/shot.webp"], result[:screenshots]
    assert_equal "https://app.example.com/product/cover.jpg", result[:header_image]
    assert_equal "https://app.example.com/information", result[:canonical_url]
    assert_equal "https://app.example.com/product/index.html", result[:final_url]
  end

  test "uses app structured data and HTML when the manifest is unavailable" do
    result = preview({
      "https://app.example.com/start" => response("https://app.example.com/start", <<~HTML)
        <title>Fallback title</title>
        <meta name="description" content="HTML description">
        <link rel="manifest" href="missing.webmanifest">
        <link rel="apple-touch-icon" href="/icon.png">
        <script type="application/ld+json">{"@graph":[{"@type":"Organization","name":"Owner"},
          {"@type":"WebApplication","name":"Actual app","screenshot":{"contentUrl":"shot.png"}}]}</script>
      HTML
    })

    assert_equal "Actual app", result[:name]
    assert_equal "HTML description", result[:description]
    assert_equal "https://app.example.com/icon.png", result[:icon_url]
    assert_equal ["https://app.example.com/shot.png"], result[:screenshots]
  end

  test "filters non-public destinations and keeps social images out of screenshots" do
    result = preview({
      "https://app.example.com/start" => response("https://app.example.com/start", <<~HTML)
        <title>Simple app</title>
        <link rel="icon" href="https://private.test/logo.png">
        <meta name="twitter:image" content="/card.png">
      HTML
    })
    assert_nil result[:icon_url]
    assert_equal "https://app.example.com/card.png", result[:header_image]
    assert_empty result[:screenshots]
  end

  test "rejects non-HTTPS and local URLs before requesting a page" do
    fetcher = FixtureFetcher.new({})
    service = MiniAppWebsitePreview.new(fetcher: fetcher)
    assert_raises(PublicWebsiteFetch::Unavailable) { service.call("http://example.com/") }
    assert_raises(PublicWebsiteFetch::Unavailable) { service.call("https://localhost/") }
    assert_raises(PublicWebsiteFetch::Unavailable) { service.call("https://user@example.com/") }
    refute PublicWebsiteFetch.new.public_destination?(URI("https://127.0.0.1/"))
  end

  private

  def preview(fixtures)
    MiniAppWebsitePreview.new(fetcher: FixtureFetcher.new(fixtures)).call("https://app.example.com/start")
  end

  def response(url, body)
    PublicWebsiteFetch::Response.new(url: URI(url), body: body, content_type: "text/html")
  end
end
