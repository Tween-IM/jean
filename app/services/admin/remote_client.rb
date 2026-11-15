require "net/http"
require "json"
require "uri"

module Admin
  class RemoteClient
    class Unavailable < StandardError; end
    class Forbidden < StandardError; end
    class NotFound < StandardError; end
    class Rejected < StandardError; end

    def initialize(url:, token:)
      @url = url.to_s.chomp("/")
      @token = token.to_s
    end

    def get(path, query = {})
      request(:get, path, query: query)
    end

    def request(method, path, query: {}, body: nil)
      raise Unavailable, "This connection has not been configured." if @url.blank? || @token.blank?
      uri = URI.parse(@url + path)
      unless uri.is_a?(URI::HTTP) && (uri.scheme == "https" || !Rails.env.production?) && uri.userinfo.nil?
        raise Unavailable, "This connection requires a secure service URL."
      end
      uri.query = URI.encode_www_form(query.compact) if query.any?
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 3
      http.read_timeout = 8
      klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put, delete: Net::HTTP::Delete }.fetch(method)
      req = klass.new(uri.request_uri)
      req["Authorization"] = "Bearer #{@token}"
      req["Accept"] = "application/json"
      if body
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(body)
      end
      response = http.request(req)
      raise Forbidden, "You do not have access to this information." if %w[401 403].include?(response.code)
      raise NotFound, "No matching record was found." if response.code == "404"
      if %w[400 409 422].include?(response.code)
        raise Rejected, "The action was rejected. Refresh the record and check its current state before trying again."
      end
      raise Unavailable, "The service could not complete this request." unless response.is_a?(Net::HTTPSuccess)
      payload = response.body.present? ? JSON.parse(response.body) : {}
      raise Unavailable, "The service returned an unexpected response." unless payload.is_a?(Hash)
      payload
    rescue URI::InvalidURIError, JSON::ParserError, Net::ProtocolError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
      raise Unavailable, "This information is temporarily unavailable. Please try again."
    end

    def segment(value)
      URI.encode_www_form_component(value.to_s).gsub("+", "%20")
    end
  end
end
