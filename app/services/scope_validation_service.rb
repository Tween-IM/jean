class ScopeValidationService
  TMCP_SCOPES = %w[
    user:read
    user:read:extended
    user:read:contacts
    wallet:balance
    wallet:pay
    wallet:history
    wallet:request
    messaging:send
    messaging:read
    storage:read
    storage:write
    webhook:send
    room:create
    room:invite
  ].freeze

  MATRIX_SCOPES = %w[
    openid
    urn:matrix:org.matrix.msc2967.client:api:*
    urn:matrix:org.matrix.msc2967.client:device:*
    urn:synapse:admin:*
    urn:mas:admin
  ].freeze

  ADMIN_SCOPES = %w[
    urn:synapse:admin:*
    urn:mas:admin
  ].freeze

  SENSITIVE_SCOPES = %w[
    wallet:pay
    wallet:history
    messaging:send
    messaging:read
    room:create
    room:invite
    user:read:contacts
  ].freeze

  class ScopeError < StandardError
    attr_reader :code, :details

    def initialize(code, message, details = {})
      super(message)
      @code = code
      @details = details
    end
  end

  def validate_scopes(requested_scopes, miniapp_id, user_id = nil)
    valid = []
    denied = []

    requested_scopes.each do |scope|
      if valid_tmcp_scope?(scope) || valid_matrix_scope?(scope)
        if sensitive_scope?(scope) && user_id
          valid << {
            scope: scope,
            status: "pending_approval",
            requires_user_consent: true
          }
        else
          valid << {
            scope: scope,
            status: "approved",
            requires_user_consent: sensitive_scope?(scope)
          }
        end
      else
        denied << {
          scope: scope,
          reason: "not_registered",
          message: "Scope '#{scope}' is not registered for this mini-app"
        }
      end
    end

    {
      valid: valid,
      denied: denied,
      approved: valid.reject { |s| s[:status] == "pending_approval" },
      pending_approval: valid.select { |s| s[:status] == "pending_approval" }
    }
  end

  def parse_scope_string(scope_string)
    scope_string.to_s.split(/\s+/).map(&:strip).reject(&:blank?)
  end

  def separate_scopes(scopes)
    scopes.partition { |s| valid_tmcp_scope?(s) }
  end

  def validate_tmcp_scopes(scopes)
    scopes.each do |scope|
      unless valid_tmcp_scope?(scope)
        raise ScopeError.new(
          "INVALID_SCOPE",
          "Invalid TMCP scope: #{scope}",
          scope: scope
        )
      end
    end
    true
  end

  def validate_matrix_scopes(scopes)
    scopes.each do |scope|
      unless valid_matrix_scope?(scope)
        raise ScopeError.new(
          "INVALID_MATRIX_SCOPE",
          "Invalid Matrix scope: #{scope}",
          scope: scope
        )
      end
    end
    true
  end

  def is_sensitive_scope?(scope)
    SENSITIVE_SCOPES.include?(scope.to_s)
  end

  def requires_user_approval?(scope)
    SENSITIVE_SCOPES.include?(scope.to_s)
  end

  def valid_tmcp_scope?(scope)
    return false if scope.blank?
    TMCP_SCOPES.include?(scope.to_s)
  end

  def valid_matrix_scope?(scope)
    return false if scope.blank?
    return true if MATRIX_SCOPES.include?(scope.to_s)

    scope.start_with?("urn:matrix:") || scope.start_with?("urn:synapse:") || scope.start_with?("urn:mas:")
  end

  def is_admin_scope?(scope)
    ADMIN_SCOPES.include?(scope.to_s)
  end

  def format_scope_for_mas(scopes)
    scopes.select { |s| valid_matrix_scope?(s) }.join(" ")
  end

  def format_scope_for_tep(scopes)
    scopes.select { |s| valid_tmcp_scope?(s) }.join(" ")
  end

  def get_scope_description(scope)
    descriptions = {
      "user:read" => "Read basic profile (name, avatar)",
      "user:read:extended" => "Read extended profile (status, bio)",
      "user:read:contacts" => "Read friend list",
      "wallet:balance" => "Read wallet balance",
      "wallet:pay" => "Process payments",
      "wallet:history" => "Read transaction history",
      "wallet:request" => "Request payments from users",
      "messaging:send" => "Send messages to rooms",
      "messaging:read" => "Read message history",
      "storage:read" => "Read mini-app storage",
      "storage:write" => "Write to mini-app storage",
      "webhook:send" => "Receive webhook callbacks",
      "room:create" => "Create new rooms",
      "room:invite" => "Invite users to rooms",
      "openid" => "OpenID Connect authentication",
      "urn:matrix:org.matrix.msc2967.client:api:*" => "Full Matrix C-S API access"
    }

    descriptions[scope.to_s] || scope.to_s
  end

  def get_scope_sensitivity(scope)
    return "critical" if %w[wallet:pay].include?(scope.to_s)
    return "high" if SENSITIVE_SCOPES.include?(scope.to_s)
    return "medium" if %w[user:read:extended wallet:balance wallet:history].include?(scope.to_s)
    "low"
  end

  def check_scope_registration(miniapp_id, requested_scopes)
    miniapp = MiniApp.find_by(app_id: miniapp_id)

    raise ScopeError.new("NOT_FOUND", "Mini-app not found") unless miniapp

    registered_scopes = miniapp.manifest["permissions"] || []

    unregistered = requested_scopes.reject { |s| registered_scopes.include?(s) }

    if unregistered.any?
      raise ScopeError.new(
        "ESCALATION_ATTEMPT",
        "Mini-app requested unregistered scopes",
        scopes: unregistered
      )
    end

    true
  end
end
