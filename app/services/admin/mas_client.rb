module Admin
  class MasClient < RemoteClient
    def initialize
      url = (ENV["MAS_ADMIN_URL"].presence || ENV["MAS_AUTH_URL"].presence || ENV["MAS_URL"]).to_s.chomp("/")
      token = ENV["MAS_ADMIN_TOKEN"].presence || client_token(url)
      super(url: url, token: token)
    end

    def account_action(id, action)
      raise Forbidden, "This action is not permitted." unless %w[lock unlock].include?(action)
      request(:post, "/api/admin/v1/users/#{segment(id)}/#{action}", body: {})
    end

    def person(id)
      raise NotFound, "No identity account is linked." if id.blank?
      get("/api/admin/v1/users/#{segment(id)}").fetch("data").fetch("attributes")
        .slice("username", "created_at", "locked_at", "deactivated_at")
    rescue KeyError, TypeError, NoMethodError
      raise Unavailable, "The identity service returned an unexpected response."
    end
    private

    def client_token(url)
      id = ENV["MAS_ADMIN_CLIENT_ID"]
      secret = ENV["MAS_ADMIN_CLIENT_SECRET"]
      return nil if url.blank? || id.blank? || secret.blank?
      uri = URI.parse("#{url}/oauth2/token")
      unless uri.is_a?(URI::HTTP) && (uri.scheme == "https" || !Rails.env.production?) && uri.userinfo.nil?
        raise Unavailable, "This connection requires a secure service URL."
      end
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 3
      http.read_timeout = 8
      req = Net::HTTP::Post.new(uri.request_uri)
      req.basic_auth(id, secret)
      req.set_form_data(grant_type: "client_credentials", scope: "urn:mas:admin")
      response = http.request(req)
      raise Unavailable, "The identity service could not authorize this connection." unless response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body).fetch("access_token")
    rescue URI::InvalidURIError, JSON::ParserError, KeyError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
      raise Unavailable, "The identity service is temporarily unavailable. Please try again."
    end
  end
end
