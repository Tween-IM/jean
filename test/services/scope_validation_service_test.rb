require "test_helper"

class ScopeValidationServiceTest < ActiveSupport::TestCase
  setup do
    @validator = ScopeValidationService.new
  end

  test "TMCP_SCOPES contains all required scopes" do
    expected_scopes = %w[
      user:read user:read:extended user:read:contacts
      wallet:balance wallet:pay wallet:history wallet:request
      messaging:send messaging:read
      storage:read storage:write webhook:send
      room:create room:invite
    ]

    expected_scopes.each do |scope|
      assert_includes ScopeValidationService::TMCP_SCOPES, scope, "Missing TMCP scope: #{scope}"
    end
  end

  test "MATRIX_SCOPES contains Matrix scope formats" do
    assert_includes ScopeValidationService::MATRIX_SCOPES, "openid"
    assert_includes ScopeValidationService::MATRIX_SCOPES, "urn:matrix:org.matrix.msc2967.client:api:*"
    assert_includes ScopeValidationService::MATRIX_SCOPES, "urn:matrix:org.matrix.msc2967.client:device:*"
  end

  test "SENSITIVE_SCOPES identifies high-risk scopes" do
    sensitive = ScopeValidationService::SENSITIVE_SCOPES

    assert_includes sensitive, "wallet:pay"
    assert_includes sensitive, "wallet:history"
    assert_includes sensitive, "messaging:send"
    assert_includes sensitive, "messaging:read"
    assert_includes sensitive, "room:create"
  end

  test "#valid_tmcp_scope? returns true for valid scopes" do
    assert @validator.valid_tmcp_scope?("wallet:pay")
    assert @validator.valid_tmcp_scope?("storage:read")
    assert @validator.valid_tmcp_scope?("user:read")
    assert @validator.valid_tmcp_scope?("room:create")
  end

  test "#valid_tmcp_scope? returns false for invalid scopes" do
    assert_not @validator.valid_tmcp_scope?("invalid:scope")
    assert_not @validator.valid_tmcp_scope?("")
    assert_not @validator.valid_tmcp_scope?(nil)
  end

  test "#valid_matrix_scope? returns true for Matrix scopes" do
    assert @validator.valid_matrix_scope?("openid")
    assert @validator.valid_matrix_scope?("urn:matrix:org.matrix.msc2967.client:api:*")
    assert @validator.valid_matrix_scope?("urn:synapse:admin:*")
  end

  test "#is_sensitive_scope? identifies sensitive scopes" do
    assert @validator.is_sensitive_scope?("wallet:pay")
    assert @validator.is_sensitive_scope?("messaging:send")
    assert @validator.is_sensitive_scope?("room:create")
    assert @validator.is_sensitive_scope?("user:read:contacts")

    assert_not @validator.is_sensitive_scope?("storage:read")
    assert_not @validator.is_sensitive_scope?("user:read")
  end

  test "#parse_scope_string splits scope string" do
    scopes = @validator.parse_scope_string("wallet:pay storage:read messaging:send")

    assert_equal 3, scopes.length
    assert_includes scopes, "wallet:pay"
    assert_includes scopes, "storage:read"
    assert_includes scopes, "messaging:send"
  end

  test "#parse_scope_string handles empty string" do
    scopes = @validator.parse_scope_string("")

    assert_empty scopes
  end

  test "#separate_scopes separates TMCP and Matrix scopes" do
    all_scopes = [ "wallet:pay", "openid", "storage:read", "urn:matrix:org.matrix.msc2967.client:api:*" ]

    tmcp, matrix = @validator.separate_scopes(all_scopes)

    assert_equal 2, tmcp.length
    assert_equal 2, matrix.length
    assert_includes tmcp, "wallet:pay"
    assert_includes tmcp, "storage:read"
    assert_includes matrix, "openid"
    assert_includes matrix, "urn:matrix:org.matrix.msc2967.client:api:*"
  end

  test "#get_scope_description returns descriptions" do
    assert_equal "Process payments", @validator.get_scope_description("wallet:pay")
    assert_equal "Read wallet balance", @validator.get_scope_description("wallet:balance")
    assert_equal "Full Matrix C-S API access", @validator.get_scope_description("urn:matrix:org.matrix.msc2967.client:api:*")
  end

  test "#get_scope_sensitivity returns correct levels" do
    assert_equal "critical", @validator.get_scope_sensitivity("wallet:pay")
    assert_equal "high", @validator.get_scope_sensitivity("wallet:history")
    assert_equal "medium", @validator.get_scope_sensitivity("wallet:balance")
    assert_equal "low", @validator.get_scope_sensitivity("storage:read")
  end

  test "#format_scope_for_mas filters to Matrix scopes only" do
    all = "wallet:pay storage:read openid urn:matrix:org.matrix.msc2967.client:api:*"

    mas_scopes = @validator.format_scope_for_mas(all.split)

    assert_equal "openid urn:matrix:org.matrix.msc2967.client:api:*", mas_scopes
  end

  test "#format_scope_for_tep filters to TMCP scopes only" do
    all = "wallet:pay storage:read openid urn:matrix:org.matrix.msc2967.client:api:*"

    tep_scopes = @validator.format_scope_for_tep(all.split)

    assert_equal "wallet:pay storage:read", tep_scopes
  end
end
