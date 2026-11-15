require "jwt"

module TweenPay
  class AdminClient < Admin::RemoteClient
    def initialize(actor)
      @actor = actor
      secret = ENV["TWEEN_ADMIN_SECRET"].to_s
      token = if secret.bytesize >= 32
        JWT.encode({ iss: "tween-admin", aud: "tween-pay-admin", sub: actor.matrix_user_id,
          iat: Time.current.to_i, exp: 1.minute.from_now.to_i }, secret, "HS256")
      end
      super(url: ENV["TWEEN_PAY_ADMIN_URL"].presence || ENV["WALLET_API_BASE_URL"], token: token)
    end

    def list(resource, query = {})
      data = get("/internal/admin/v1/resources/#{segment(resource)}", query)
      raise Unavailable, "The service returned an unexpected response." unless data["records"].is_a?(Array)
      data
    end

    def detail(resource, id)
      data = get("/internal/admin/v1/resources/#{segment(resource)}/#{segment(id)}")
      raise Unavailable, "The service returned an unexpected response." unless data["record"].is_a?(Hash)
      data
    end

    def person(matrix_id)
      data = get("/internal/admin/v1/person", matrix_user_id: matrix_id)
      raise Unavailable, "The service returned an unexpected response." unless data["user"].is_a?(Hash)
      data
    end

    def card_options
      get("/internal/admin/v1/card_options")
    end

    def evidence(id, resource: "identity_documents", **query)
      get("/internal/admin/v1/resources/#{segment(resource)}/#{segment(id)}/evidence", query)
    end

    def command(resource, id, action:, reason:, request_id:, value: nil)
      request(:post, "/internal/admin/v1/resources/#{segment(resource)}/#{segment(id)}/commands",
        body: { operation: action, reason: reason, request_id: request_id, value: value })
    end
  end
end
