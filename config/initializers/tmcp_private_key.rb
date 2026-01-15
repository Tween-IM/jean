# frozen_string_literal: true

# Load TMCP private key from file for JWT signing
# This keeps sensitive keys out of environment variables and docker-compose.yml

require "fileutils"

module TmcpPrivateKeyLoader
  KEY_PATH = ENV.fetch("TMCP_PRIVATE_KEY_FILE", "/run/secrets/tmcp_private_key")

  class << self
    def load
      return if ENV["TMCP_PRIVATE_KEY"].present?

      if File.exist?(KEY_PATH)
        key_content = File.read(KEY_PATH).strip
        ENV["TMCP_PRIVATE_KEY"] = key_content
        Rails.logger.info "Loaded TMCP private key from #{KEY_PATH}"
      else
        Rails.logger.warn "TMCP private key file not found at #{KEY_PATH}"
      end
    end
  end
end

# Load when Rails boots
TmcpPrivateKeyLoader.load
