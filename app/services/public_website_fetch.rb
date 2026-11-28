# frozen_string_literal: true

require "ipaddr"
require "net/http"
require "socket"
require "timeout"
require "uri"

# Fetches anonymous HTTPS resources for the staff listing preview.
class PublicWebsiteFetch
  class Unavailable < StandardError; end

  Response = Data.define(:url, :body, :content_type)

  NON_PUBLIC_V4 = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
    172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.88.99.0/24 192.168.0.0/16
    198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/3
  ].map { |prefix| IPAddr.new(prefix) }.freeze
  GLOBAL_V6 = IPAddr.new("2000::/3")
  NON_PUBLIC_V6 = %w[2001::/23 2001:db8::/32 2002::/16 3fff::/20].map { |prefix| IPAddr.new(prefix) }.freeze

  def self.url(value, base: nil)
    return unless value.is_a?(String) && value.bytesize.between?(1, 4096)

    uri = base ? URI.join(base.to_s, value.strip) : URI.parse(value.strip)
    return unless uri.is_a?(URI::HTTPS) && uri.port == 443 && uri.userinfo.nil?
    return unless uri.hostname&.match?(/\A[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\z/i)
    return unless uri.hostname.include?(".")
    return if uri.hostname.match?(/\.(?:localhost|local|internal|home\.arpa)\z/i)

    uri.fragment = nil
    uri
  rescue URI::Error, ArgumentError
    nil
  end

  def public_destination?(uri)
    Timeout.timeout(1) { public_addresses(uri).any? }
  rescue Unavailable, Timeout::Error, SocketError, SystemCallError
    false
  end

  def get(uri, accept:, max_bytes:, &allowed_type)
    Timeout.timeout(5) do
      4.times do
        raise Unavailable unless uri

        addresses = public_addresses(uri)

        # Preserve SNI and certificate verification for the host while pinning the connection.
        http = Net::HTTP.new(uri.hostname, 443, nil)
        http.ipaddr = addresses.first.to_s
        http.use_ssl = true
        http.open_timeout = 2
        http.read_timeout = 2
        http.max_retries = 0

        http.start do |connection|
          request = Net::HTTP::Get.new(uri.request_uri, {
            "Accept" => accept,
            "Accept-Encoding" => "identity",
            "User-Agent" => "TweenListingPreview/1.0"
          })
          connection.request(request) do |remote|
            if %w[301 302 303 307 308].include?(remote.code)
              location = remote["location"]
              uri = self.class.url(location, base: uri)
              # Stop reading the redirect response before following its Location.
              break
            end

            raise Unavailable unless remote.is_a?(Net::HTTPSuccess)
            raise Unavailable unless [nil, "identity"].include?(remote["content-encoding"])
            type = remote["content-type"].to_s.split(";").first.to_s.strip.downcase
            raise Unavailable unless allowed_type.call(type)
            raise Unavailable if remote["content-length"].to_i > max_bytes

            body = String.new(encoding: Encoding::BINARY)
            remote.read_body do |chunk|
              raise Unavailable if body.bytesize + chunk.bytesize > max_bytes

              body << chunk
            end
            return Response.new(url: uri, body: body, content_type: type)
          end
        end
      end
      raise Unavailable
    end
  rescue Timeout::Error, SocketError, SystemCallError, IOError, Net::ProtocolError, OpenSSL::SSL::SSLError
    raise Unavailable
  end

  private

  def public_addresses(uri)
    addresses = Addrinfo.getaddrinfo(uri.hostname, 443, nil, :STREAM)
      .map { |address| IPAddr.new(address.ip_address).native }.uniq
    raise Unavailable if addresses.empty? || addresses.any? { |address| !public_ip?(address) }

    addresses
  end

  def public_ip?(address)
    if address.ipv4?
      NON_PUBLIC_V4.none? { |range| range.include?(address) }
    else
      GLOBAL_V6.include?(address) && NON_PUBLIC_V6.none? { |range| range.include?(address) }
    end
  end
end
