# frozen_string_literal: true

require "json"
require "nokogiri"

class MiniAppWebsitePreview
  MAX_SCREENSHOTS = 6
  APP_TYPES = %w[SoftwareApplication WebApplication MobileApplication].freeze

  def initialize(fetcher: PublicWebsiteFetch.new)
    @fetcher = fetcher
    @asset_hosts = {}
  end

  def call(raw_url)
    url = PublicWebsiteFetch.url(raw_url)
    raise PublicWebsiteFetch::Unavailable unless url

    page = @fetcher.get(url, accept: "text/html, application/xhtml+xml", max_bytes: 1_500_000) do |type|
      %w[text/html application/xhtml+xml].include?(type)
    end
    html = Nokogiri::HTML5(page.body)
    base = PublicWebsiteFetch.url(html.at_css("base[href]")&.[]("href"), base: page.url) || page.url
    meta = metadata(html)
    manifest, manifest_url = read_manifest(html, base)
    app = structured_app(html, page.url)
    icon = best_icon(manifest, app, html, manifest_url, base, page.url)
    screenshots = image_urls(manifest["screenshots"], manifest_url, key: "src") +
      image_urls(app["screenshot"], base)
    cover = %w[og:image:secure_url og:image og:image:url twitter:image twitter:image:src]
      .lazy.filter_map { |key| asset_url(meta[key], base) }.first || image_urls(app["image"], base).first

    {
      name: clean(120, manifest["name"], manifest["short_name"], app["name"], meta["og:title"], meta["twitter:title"],
        html.at_css("title")&.text, html.at_css("main h1, h1")&.text),
      description: clean(2000, manifest["description"], app["description"], meta["og:description"],
        meta["twitter:description"], meta["description"], html.at_css("main p, article p")&.text),
      icon_url: icon,
      header_image: cover,
      screenshots: screenshots.uniq.first(MAX_SCREENSHOTS),
      final_url: page.url.to_s,
      canonical_url: PublicWebsiteFetch.url(link(html, "canonical"), base: base)&.to_s
    }.compact
  end

  private

  def metadata(html)
    html.css("meta[content]").each_with_object({}) do |node, values|
      key = (node["property"] || node["name"]).to_s.downcase
      content = node["content"].to_s.strip
      values[key] ||= content unless content.empty?
    end
  end

  def link(html, rel)
    html.at_css("link[rel~='#{rel}'][href]")&.[]("href")
  end

  def read_manifest(html, base)
    url = PublicWebsiteFetch.url(link(html, "manifest"), base: base)
    return [{}, base] unless url

    asset = @fetcher.get(url, accept: "application/manifest+json, application/json", max_bytes: 160_000) do |type|
      %w[application/manifest+json application/json text/plain].include?(type)
    end
    parsed = JSON.parse(asset.body)
    [parsed.is_a?(Hash) ? parsed : {}, asset.url]
  rescue PublicWebsiteFetch::Unavailable, JSON::ParserError
    [{}, base]
  end

  def structured_app(html, page_url)
    nodes = html.css("script[type='application/ld+json']").first(12).flat_map do |script|
      value = JSON.parse(script.content)
      value.is_a?(Array) ? value : [value]
    rescue JSON::ParserError
      []
    end
    apps = nodes.grep(Hash).flat_map do |node|
      [node, *Array(node["@graph"]), node["mainEntity"]]
    end.grep(Hash).select do |node|
      Array(node["@type"]).any? { |type| APP_TYPES.include?(type.to_s.split("/").last) }
    end
    apps.find { |app| PublicWebsiteFetch.url(app["url"], base: page_url) == page_url } ||
      (apps.one? ? apps.first : {})
  end

  def best_icon(manifest, app, html, manifest_url, base, page_url)
    icons = Array(manifest["icons"]).grep(Hash).reject do |icon|
      icon["purpose"].present? && !icon["purpose"].to_s.split.include?("any")
    end
    icons = icons.sort_by { |icon| -icon["sizes"].to_s.scan(/(\d+)x\1\b/).flatten.map(&:to_i).max.to_i }
    image_urls(icons, manifest_url, key: "src").first ||
      image_urls(app["logo"], base).first ||
      image_urls(%w[apple-touch-icon apple-touch-icon-precomposed icon].map { |rel| link(html, rel) }, base).first ||
      verified_favicon(page_url)
  end

  def verified_favicon(page_url)
    url = PublicWebsiteFetch.url("/favicon.ico", base: page_url)
    asset = @fetcher.get(url, accept: "image/*", max_bytes: 128_000) { |type| type.start_with?("image/") }
    asset.url.to_s unless asset.body.empty?
  rescue PublicWebsiteFetch::Unavailable
    nil
  end

  def image_urls(value, base, key: nil)
    items = value.is_a?(Array) ? value : [value]
    items.first(24).filter_map do |item|
      raw = item.is_a?(Hash) ? (key ? item[key] : item["contentUrl"] || item["url"]) : item
      asset_url(raw, base)
    end
  end

  def asset_url(value, base)
    uri = PublicWebsiteFetch.url(value, base: base)
    return unless uri

    host = uri.hostname.downcase
    unless @asset_hosts.key?(host)
      return if @asset_hosts.size >= 5

      @asset_hosts[host] = @fetcher.public_destination?(uri)
    end
    uri.to_s if @asset_hosts[host]
  end

  def clean(limit, *values)
    clean = values.grep(String).filter_map do |value|
      text = value.gsub(/[[:space:]]+/, " ").strip
      text.first(limit) unless text.empty?
    end
    clean.first
  end
end
