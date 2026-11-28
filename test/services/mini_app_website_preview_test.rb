# frozen_string_literal: true

require "test_helper"

class MiniAppWebsitePreviewTest < ActiveSupport::TestCase
  class FixtureFetcher
    def initialize(fixtures)
      @fixtures = fixtures
    end

    def get(url, accept:, max_bytes:, &allowed_type)
      response = @fixtures.fetch(url.to_s) { raise PublicWebsiteFetch::Unavailable }
      raise PublicWebsiteFetch::Unavailable if allowed_type && !allowed_type.call(response.content_type)

      response
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
    manifest = response("https://assets.example.com/v2/app.webmanifest", <<~JSON, content_type: "application/manifest+json")
      {"name":"Product","description":"A useful app","icons":[
        {"src":"tiny.png","sizes":"32x32"},{"src":"mask.png","sizes":"512x512","purpose":"maskable"},
        {"src":"icon.png","sizes":"192x192"}],
      "screenshots":[{"src":"shot.webp"},{"src":"shot.webp"},{"src":"https://private.test/x.png"}]}
    JSON
    result = preview({
      "https://app.example.com/start" => page,
      "https://app.example.com/product/app.webmanifest" => manifest,
      "https://assets.example.com/v2/icon.png" => image("https://assets.example.com/v2/icon.png")
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
    page = response("https://app.example.com/start", <<~HTML)
      <title>Fallback title</title>
      <meta name="description" content="HTML description">
      <link rel="manifest" href="missing.webmanifest">
      <link rel="apple-touch-icon" href="/icon.png">
      <script type="application/ld+json">{"@graph":[{"@type":"Organization","name":"Owner"},
        {"@type":"WebApplication","name":"Actual app","screenshot":{"contentUrl":"shot.png"}}]}</script>
    HTML
    result = preview({
      "https://app.example.com/start" => page,
      "https://app.example.com/icon.png" => image("https://app.example.com/icon.png")
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

  test "falls back to the site root icon when manifest and link icons are missing" do
    page = response("https://app.example.com/start", <<~HTML)
      <title>OLE</title>
      <link rel="manifest" href="manifest.json">
      <link rel="icon" href="icons/icon-192.png">
      <link rel="apple-touch-icon" href="icons/apple-touch-icon.png">
    HTML
    manifest = response("https://app.example.com/manifest.json", <<~JSON, content_type: "application/manifest+json")
      {"name":"OLE","icons":[{"src":"icons/icon-512.png","sizes":"512x512"}]}
    JSON
    result = preview({
      "https://app.example.com/start" => page,
      "https://app.example.com/manifest.json" => manifest,
      "https://app.example.com/icon-512.png" => image("https://app.example.com/icon-512.png")
    })

    assert_equal "https://app.example.com/icon-512.png", result[:icon_url]
  end

  test "skips icon URLs that do not serve a raster image" do
    page = response("https://app.example.com/start", <<~HTML)
      <title>Product</title>
      <link rel="manifest" href="manifest.json">
    HTML
    manifest = response("https://app.example.com/manifest.json", <<~JSON, content_type: "application/manifest+json")
      {"name":"Product","icons":[{"src":"icon-512.png","sizes":"512x512"},{"src":"icon-192.png","sizes":"192x192"}]}
    JSON
    result = preview({
      "https://app.example.com/start" => page,
      "https://app.example.com/manifest.json" => manifest,
      "https://app.example.com/icon-512.png" => response("https://app.example.com/icon-512.png", "<html>404</html>"),
      "https://app.example.com/icon-192.png" => image("https://app.example.com/icon-192.png")
    })

    assert_equal "https://app.example.com/icon-192.png", result[:icon_url]
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

  def response(url, body, content_type: "text/html")
    PublicWebsiteFetch::Response.new(url: URI(url), body: body, content_type: content_type)
  end

  def image(url)
    PublicWebsiteFetch::Response.new(url: URI(url), body: "icon".b, content_type: "image/png")
  end
end
