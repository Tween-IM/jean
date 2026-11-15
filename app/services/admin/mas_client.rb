module Admin
  class MasClient < RemoteClient
    def initialize(grant:)
      @grant = grant
      url = (ENV["MAS_ADMIN_URL"].presence || ENV["MAS_AUTH_URL"].presence || ENV["MAS_URL"]).to_s.chomp("/")
      token = grant.access_token_for(AdminOauthGrant::MAS_SCOPE)
      super(url: url, token: token)
    end

    def request(...)
      super
    rescue RemoteClient::Unauthorized
      @grant.destroy!
      raise AdminOauthGrant::ConnectionRequired, AdminOauthGrant::MESSAGE
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
  end
end
