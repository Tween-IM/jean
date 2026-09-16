# frozen_string_literal: true

require "base64"
require "digest"
require "json"
require "net/http"
require "securerandom"
require "uri"

module Admin
  # Sign-in for platform staff through Tween's Matrix Authentication Service.
  #
  # MAS is the identity provider, and the only place a password is ever typed:
  # jean runs the OIDC authorization-code + PKCE flow, then maps the returned
  # subject (the MAS user id) onto `users.mas_user_id` and requires the account
  # to be a platform admin. jean never sees or stores a password.
  #
  # The redirect URI must be registered on the MAS client:
  #   MAS_ADMIN_REDIRECT_URI (defaults to <SERVICE_URL_RAILS>/admin/auth/mas/callback)
  #
  # Credentials are the same confidential-client pair jean already uses for
  # token exchange: MAS_CLIENT_ID, and MAS_CLIENT_SECRET (or
  # MAS_CLIENT_SECRET_FILE).
  class MasOidc
    class Error < StandardError; end
    class NotConfiguredError < Error; end

    AUTHORIZE_PATH = "/authorize"
    TOKEN_PATH = "/oauth2/token"
    USERINFO_PATH = "/oauth2/userinfo"
    SCOPE = "openid"
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    class << self
      def configured?
        issuer.present? && client_id.present? && client_secret.present?
      end

      def issuer
        (ENV["MAS_AUTH_URL"] || ENV["MAS_URL"]).to_s.chomp("/").presence
      end

      def client_id
        ENV["MAS_CLIENT_ID"].presence
      end

      def client_secret
        ENV["MAS_CLIENT_SECRET"].presence || secret_from_file
      end

      def secret_from_file
        path = ENV["MAS_CLIENT_SECRET_FILE"].presence
        return nil if path.nil?

        File.read(path).strip.presence
      rescue Errno::ENOENT, Errno::EACCES
        nil
      end

      # Where MAS sends the browser back. MAS validates this against the
      # client registration, so it is configurable per environment.
      def redirect_uri
        ENV["MAS_ADMIN_REDIRECT_URI"].presence ||
          "#{ENV.fetch('SERVICE_URL_RAILS', 'http://localhost:3000').to_s.chomp('/')}/admin/auth/mas/callback"
      end

      def authorization_url(state:, code_verifier:)
        raise NotConfiguredError, "Tween ID sign-in is not configured" unless configured?

        query = URI.encode_www_form(
          response_type: "code",
          client_id: client_id,
          redirect_uri: redirect_uri,
          scope: SCOPE,
          state: state,
          code_challenge: code_challenge(code_verifier),
          code_challenge_method: "S256"
        )
        "#{issuer}#{AUTHORIZE_PATH}?#{query}"
      end

      def new_code_verifier
        SecureRandom.urlsafe_base64(48)
      end

      def new_state
        SecureRandom.urlsafe_base64(32)
      end

      def code_challenge(verifier)
        Base64.urlsafe_encode64(Digest::SHA256.digest(verifier.to_s), padding: false)
      end

      # Exchanges the authorization code for tokens and returns the OIDC claims.
      def claims_for(code:, code_verifier:)
        raise NotConfiguredError, "Tween ID sign-in is not configured" unless configured?

        token = post(TOKEN_PATH, {
          grant_type: "authorization_code",
          code: code,
          redirect_uri: redirect_uri,
          client_id: client_id,
          client_secret: client_secret,
          code_verifier: code_verifier
        })

        access_token = token["access_token"].to_s
        raise Error, "MAS returned no access token" if access_token.blank?

        get(USERINFO_PATH, "Authorization" => "Bearer #{access_token}")
      end

      # The userinfo claims name the MAS user id (`sub`) and, depending on
      # scopes, a Matrix id. Either is enough to find the mapping jean already
      # keeps for every user it knows about.
      def user_for(claims)
        mas_user_id = claims["sub"].to_s.presence
        matrix_user_id = claims["matrix_user_id"].to_s.presence

        user = User.find_by(mas_user_id: mas_user_id) if mas_user_id
        user ||= User.find_by(matrix_user_id: matrix_user_id) if matrix_user_id&.start_with?("@")
        user
      end

      private

      def post(path, form)
        request(
          Net::HTTP::Post,
          path,
          URI.encode_www_form(form),
          "Content-Type" => "application/x-www-form-urlencoded",
          "Accept" => "application/json"
        )
      end

      def get(path, headers = {})
        request(Net::HTTP::Get, path, nil, { "Accept" => "application/json" }.merge(headers))
      end

      def request(verb, path, body, headers)
        uri = URI.parse("#{issuer}#{path}")
        raise Error, "MAS URL is not a valid HTTP endpoint" unless uri.is_a?(URI::HTTP)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT

        request = verb.new(uri.request_uri)
        headers.each { |name, value| request[name] = value }
        request.body = body if body

        parse(http.request(request), path)
      rescue Error
        raise
      rescue StandardError => e
        raise Error, "could not reach Tween ID (#{e.class}: #{e.message})"
      end

      def parse(response, context)
        payload = parse_body(response.body)
        return payload if response.is_a?(Net::HTTPSuccess)

        detail = payload["error_description"].presence || payload["error"].presence || "HTTP #{response.code}"
        raise Error, "Tween ID rejected #{context}: #{detail}"
      end

      def parse_body(body)
        text = body.to_s
        return {} if text.blank?

        parsed = JSON.parse(text)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end
    end
  end
end
