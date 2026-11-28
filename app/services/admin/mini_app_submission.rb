require "uri"
require "openssl"
require "digest"

module Admin
  # Stores reviewed launch configuration and immutable, signed distribution artifacts.
  class MiniAppSubmission
    class Invalid < StandardError; end
    def self.call(app:, attributes:, manifest:, upload: nil)
      previous_version = app.version
      values = attributes.to_h.stringify_keys.except("status")
      raise Invalid, 'Use a semantic version such as 1.0.0.' unless values['version'].to_s.match?(/\A\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?\z/)
      begin
        app.assign_attributes(values)
      rescue ArgumentError
        raise Invalid, 'Check the app classification and client type.'
      end
      config = app.manifest.to_h.deep_dup
      input = manifest.to_h.stringify_keys
      %w[entry_url icon_url header_image webhook_url].each do |key|
        next unless input.key?(key)
        value = input[key].to_s.strip
        if value.present?
          uri = URI.parse(value)
          internal = key == "entry_url" && (values["classification"] || app.classification) == "official" && uri.scheme == "tween-internal"
          raise Invalid, "#{key.humanize} must be an HTTPS URL without credentials." unless internal || (uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil?)
        end
        config[key] = value
      end
      if input.key?("runtime")
        case input["runtime"]
        when "website", "tmcp"
          config["runtime"] = input["runtime"]
        when ""
          config.delete("runtime")
        else
          raise Invalid, "Choose a valid app runtime."
        end
      end
      if config["runtime"] == "website" && !config["entry_url"].to_s.start_with?("https://")
        raise Invalid, "The website runtime requires an HTTPS launch URL."
      end
      if input.key?("screenshots")
        screenshots = input["screenshots"].to_s.lines.map(&:strip).reject(&:empty?).uniq
        if screenshots.length > MiniAppWebsitePreview::MAX_SCREENSHOTS ||
            screenshots.any? { |url| PublicWebsiteFetch.url(url).nil? }
          raise Invalid, "Use up to six HTTPS screenshot URLs without credentials."
        end
        config["screenshots"] = screenshots
      end
      config["scopes"] = Array(input["permissions"]).reject(&:blank?) if input.key?("permissions")
      config["redirect_uris"] = input["redirect_uris"].to_s.lines.map(&:strip).reject(&:empty?) if input.key?("redirect_uris")
      Array(config["redirect_uris"]).each do |url|
        uri = URI.parse(url)
        raise Invalid, "Redirect URLs must use HTTPS without credentials." unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil?
      end
      raise Invalid, "A launch URL is required." if config["entry_url"].blank?
      artifact = nil
      remove_bundle = !upload && config['bundle'].present? && config.dig('bundle', 'version') != values['version']
      if remove_bundle
        raise Invalid, 'Upload a package for the new embedded version.' if config['entry_url'].to_s.start_with?('tween-internal://')
        config['previous_releases'] = Array(config['previous_releases']) + [config.delete('bundle')]
      end
      if upload
        raise Invalid, "Choose a package file." unless upload.respond_to?(:original_filename) && upload.respond_to?(:read)
        raise Invalid, "Choose a ZIP or .bundle package up to 25 MB." unless upload.size.between?(1, 25.megabytes) && upload.original_filename.match?(/\.(zip|bundle)\z/i)
        raise Invalid, "A new package requires a new version." if app.persisted? && previous_version == values["version"] && app.bundle.attached?
        bytes = upload.read
        upload.rewind
        key = OpenSSL::PKey::RSA.new(ENV.fetch("TMCP_PRIVATE_KEY", "").gsub('\\n', "\n"))
        raise Invalid, "A persistent TMCP signing key is required for bundle uploads." unless key.private?
        artifact = { "hash" => "sha256:#{Digest::SHA256.hexdigest(bytes)}", "size_bytes" => bytes.bytesize,
          "signature" => Base64.strict_encode64(key.sign(OpenSSL::Digest::SHA256.new, bytes)), "version" => values["version"] }
        previous = config['bundle']
        config['previous_releases'] = Array(config['previous_releases']) + [previous] if previous.present?
        config["bundle"] = artifact
      end
      app.assign_attributes(values.merge("manifest" => config))
      # Any configuration change returns to review; forms cannot directly publish an app.
      app.status = "pending_review"
      raise ActiveRecord::RecordInvalid, app unless app.valid?
      begin
        blob = ActiveStorage::Blob.create_and_upload!(io: upload, filename: upload.original_filename, content_type: 'application/octet-stream', service_name: MiniApp::BUNDLE_STORAGE_SERVICE.to_s) if upload
      rescue StandardError => error
        Rails.logger.warn("Mini-app package storage failed class=#{error.class}")
        raise Invalid, 'Package storage is temporarily unavailable. Try again shortly.'
      end
      MiniApp.transaction do
        app.save!
        if remove_bundle && app.bundle.attached?
          app.previous_bundles.attach(app.bundle.blob)
          app.bundle.detach
        end
        if blob
          app.previous_bundles.attach(app.bundle.blob) if app.bundle.attached?
          app.bundle.attach(blob)
        end
      end
      app
    rescue URI::InvalidURIError
      raise Invalid, "Check the launch, icon, webhook and redirect URLs."
    rescue OpenSSL::PKey::RSAError
      raise Invalid, "Bundle signing is unavailable. Configure the persistent TMCP signing key."
    end
  end
end
