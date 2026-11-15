module Admin
  class SynapseClient < RemoteClient
    def initialize(grant:)
      @grant = grant
      super(url: ENV["SYNAPSE_ADMIN_URL"].presence || ENV["MATRIX_API_URL"], token: grant.access_token_for(AdminOauthGrant::SYNAPSE_SCOPE))
    end

    def request(...)
      super
    rescue RemoteClient::Unauthorized
      @grant.destroy!
      raise AdminOauthGrant::ConnectionRequired, AdminOauthGrant::MESSAGE
    end

    def list(resource, query = {})
      endpoint, key = { "rooms" => [ "rooms", "rooms" ], "reports" => [ "event_reports", "event_reports" ] }.fetch(resource)
      page = [ query[:page].to_i, 1 ].max
      options = { from: query[:cursor].presence || "0", limit: 25 }
      options[:search_term] = query[:query] if resource == "rooms" && query[:query].present?
      data = get("/_synapse/admin/v1/#{endpoint}", options)
      raise Unavailable, "The service returned an unexpected response." unless data[key].is_a?(Array)
      { "records" => data.fetch(key).map { |record| present(record, resource) }, "total" => data["total_rooms"] || data["total"],
        "next_cursor" => data["next_batch"] || data["next_token"], "previous_cursor" => data["prev_batch"],
        "page" => page, "next_page" => (page + 1 if data["next_batch"].present? || data["next_token"].present?) }
    end

    def detail(resource, id)
      endpoint = { "rooms" => "rooms", "reports" => "event_reports" }.fetch(resource)
      { "record" => present(get("/_synapse/admin/v1/#{endpoint}/#{segment(id)}"), resource) }
    end

    def command(resource, id, action:, **)
      case [ resource, action ]
      when [ "rooms", "block" ] then request(:put, "/_synapse/admin/v1/rooms/#{segment(id)}/block", body: { block: true })
      when [ "rooms", "unblock" ] then request(:put, "/_synapse/admin/v1/rooms/#{segment(id)}/block", body: { block: false })
      when [ "reports", "dismiss" ] then request(:delete, "/_synapse/admin/v1/event_reports/#{segment(id)}")
      else raise Forbidden, "This action is not permitted."
      end
    end

    def person(matrix_id)
      get("/_synapse/admin/v2/users/#{segment(matrix_id)}").slice("name", "displayname", "deactivated", "locked", "admin", "creation_ts")
    end
    def present(record, resource)
      record.merge("title" => record["name"].presence || record["canonical_alias"].presence ||
        (resource == "reports" ? "Reported message" : "Unnamed room"),
        "subtitle" => record["canonical_alias"].presence || record["reason"].presence)
    end

  end
end
