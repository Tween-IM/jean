# frozen_string_literal: true

require "aws-sdk-s3"
require "digest"
require "pathname"

module Commerce
  # Stores operator-uploaded media in the shared system bucket and answers
  # with the URL to publish: storefront branding (logo, banner) and extra
  # product images.
  #
  # Keys live under the same folders the scraper publishes to, so an operator
  # upload and a mirrored asset sit side by side:
  #
  #   commerce/storefronts/<platform>/<kind>/<slug>/<asset>-<digest>.<ext>
  #   commerce/products/<platform>/<source id>/<asset>-<digest>.<ext>
  #   → <public base>/<bucket>/<key>
  #
  # Env: AWS_S3_BUCKET, AWS_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
  # optional AWS_S3_ENDPOINT (S3-compatible API) and S3_PUBLIC_URL (the CDN
  # that fronts the bucket; defaults to the one the scraper already uses).
  class AssetUploader
    class Error < StandardError; end
    class UnsupportedTypeError < Error; end
    class TooLargeError < Error; end

    KEY_PREFIX = "commerce"
    MAX_BYTES = 8.megabytes
    ALLOWED_TYPES = {
      "image/png" => ".png",
      "image/jpeg" => ".jpg",
      "image/jpg" => ".jpg",
      "image/webp" => ".webp",
      "image/gif" => ".gif"
    }.freeze
    ASSETS = %w[logo banner].freeze

    def initialize(bucket: nil, region: nil, endpoint: nil, public_base: nil, client: nil)
      @bucket = bucket.presence || ENV.fetch("AWS_S3_BUCKET", "tween")
      @region = region.presence || ENV.fetch("AWS_REGION", "us-east-1")
      @endpoint = endpoint.presence || ENV["AWS_S3_ENDPOINT"].presence
      @public_base = (public_base.presence || public_base_url).to_s.chomp("/")
      @client = client
    end

    attr_reader :bucket, :public_base

    # Storefront branding (logo, banner). Returns the public URL.
    def put(storefront:, asset:, io:, content_type:, filename: nil)
      asset = asset.to_s
      raise Error, "Unknown branding asset #{asset.inspect}" unless ASSETS.include?(asset)

      put_object(
        key: object_key(storefront, asset, content_type, filename),
        io: io,
        content_type: content_type
      )
    end

    # An extra image an operator adds to a listing. Returns the public URL.
    def put_media(product:, io:, content_type:, filename: nil)
      key = product_key(product, content_type, filename)

      put_object(key: key, io: io, content_type: content_type)
    end

    def put_object(key:, io:, content_type:)
      raise UnsupportedTypeError, "Use a PNG, JPEG, WebP or GIF image" unless ALLOWED_TYPES.key?(content_type.to_s)
      raise Error, "No file was uploaded" if io.nil?

      data = io.respond_to?(:read) ? io.read : io.to_s
      raise Error, "No file was uploaded" if data.blank?
      raise TooLargeError, "Images must be under #{MAX_BYTES / 1.megabyte} MB" if data.bytesize > MAX_BYTES

      client.put_object(
        bucket: @bucket,
        key: key,
        body: data,
        content_type: content_type,
        cache_control: "public, max-age=31536000, immutable"
      )

      public_url(key)
    rescue Aws::S3::Errors::ServiceError => e
      raise Error, "Could not store the image: #{e.message}"
    end

    # Deterministic per storefront + asset + content, so re-uploading the same
    # file overwrites instead of leaking objects.
    def object_key(storefront, asset, content_type, filename = nil)
      platform = storefront.source_platform.presence || "tween"
      kind = storefront.source_kind.presence || "store"
      slug = (storefront.store_url_slug.presence || storefront.slug.to_s).parameterize.presence || "store"
      digest = Digest::SHA256.hexdigest([ asset, storefront.storefront_id, content_type, filename ].join(":"))[0, 12]
      extension = ALLOWED_TYPES.fetch(content_type.to_s, File.extname(filename.to_s).presence || ".jpg")

      [
        KEY_PREFIX,
        "storefronts",
        platform.parameterize,
        kind.parameterize,
        slug,
        "#{asset}-#{digest}#{extension}"
      ].join("/")
    end

    def product_key(product, content_type, filename = nil)
      platform = product.source_platform.presence || "tween"
      source_id = (product.source_id.presence || product.product_id).to_s.parameterize.presence || "listing"
      digest = Digest::SHA256.hexdigest([ "media", product.product_id, content_type, filename ].join(":"))[0, 12]
      extension = ALLOWED_TYPES.fetch(content_type.to_s, File.extname(filename.to_s).presence || ".jpg")

      [ KEY_PREFIX, "products", platform.parameterize, source_id, "media-#{digest}#{extension}" ].join("/")
    end

    def public_url(key)
      [ @public_base, @bucket, key ].join("/")
    end

    private

    def public_base_url
      ENV["S3_PUBLIC_URL"].presence || ENV["S3_PUBLIC_BASE_URL"].presence || "https://fs.tween.im"
    end

    def client
      @client ||= begin
        options = {
          region: @region,
          access_key_id: ENV["AWS_ACCESS_KEY_ID"],
          secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"]
        }
        options[:endpoint] = @endpoint if @endpoint
        options[:force_path_style] = true if @endpoint
        Aws::S3::Client.new(**options)
      end
    end
  end
end
