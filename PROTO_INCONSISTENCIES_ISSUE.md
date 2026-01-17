---
title: "PROTO.md Logical Inconsistencies - Test Suite Failures and Data Model Issues"
labels: ["bug", "protocol-violation", "rfc-required"]
assignees: ["@mona:tween.im"]
---

## Summary

During API testing with the provided Matrix access token `mct_sb8qD8zPPZWp05qrCg3Xv90cUWtNKh_0QGYVE`, several logical inconsistencies were identified between the implementation and PROTO.md specifications, as well as within the codebase itself.

## Issues Identified

### 1. User Model Validation Inconsistency

**Location:** `app/models/user.rb:21`

**Problem:** The `matrix_username` field validation requires format `username:homeserver.domain` (regex: `/.+:.+\..+/`), but test fixtures use invalid values.

**Examples:**
- Test sets `matrix_username: "alice"` but validation requires `"alice:tween.example"`
- `matrix_user_id: "@alice:tween.example"` should correspond to `matrix_username: "alice:tween.example"`

**Affected Tests:**
- `test/controllers/api/v1/payments_controller_test.rb`
- `test/controllers/api/v1/wallet_controller_test.rb`
- `test/controllers/api/v1/storage_controller_test.rb`
- `test/controllers/api/v1/gifts_controller_test.rb`

**PROTO.md Reference:** Section 4.1 - Matrix identity mapping

### 2. OAuth Application UID Format Issues

**Location:** Various test files

**Problem:** Test fixtures create OAuth applications with UIDs that don't match registered mini-app IDs.

**Example:**
```ruby
# In oauth_controller_test.rb
matrix_user_id: "@alice#{@unique_suffix}@tween.example"  # Double @ symbol - invalid Matrix user ID format
```

**PROTO.md Reference:** Section 4.2 - OAuth 2.0 integration

### 3. Test Suite Failures Blocking Validation

**Impact:** Core payment, wallet, and storage functionality cannot be properly tested due to model validation failures.

**Error:** `ActiveRecord::RecordInvalid: Validation failed: Matrix username must be in format username:homeserver`

## Proposed Solutions

### Immediate Fixes

1. **Update User Model Validation or Test Fixtures:**
   - Either relax the regex to allow simple usernames, or
   - Update all test fixtures to use proper `username:homeserver` format

2. **Standardize Matrix User ID Format:**
   - Ensure consistent format: `@username:homeserver.domain`
   - Remove any double `@` symbols in test data

3. **Validate Mini-App to OAuth Application Mapping:**
   - Ensure test OAuth applications have UIDs matching registered mini-apps

### Protocol Compliance Checks Needed

1. **TEP Token Claims Verification:**
   - Confirm all required claims from PROTO.md Section 4.3.3 are present
   - Validate `token_type: "tep_access_token"` claim

2. **Scope Validation:**
   - Verify all scopes used in tests are defined in PROTO.md Section 2.3.3
   - Check pre-approved vs. sensitive scope classification

3. **Response Format Compliance:**
   - Ensure all API responses match PROTO.md specifications exactly

## Testing Results

### ✅ Successful Tests
- Matrix Session Delegation flow
- Device Authorization Grant (partial - MAS not available)
- Wallet balance and transactions
- Storage CRUD operations
- Payment request creation
- OAuth consent flow

### ❌ Failed Tests
- Payment controller tests (due to User model validation)
- Related controller tests with similar validation issues

## Impact Assessment

**Severity:** High - Test suite failures prevent validation of core TMCP functionality.

**Scope:** Affects payment processing, wallet operations, and data storage - critical TMCP features.

**Timeline:** Should be addressed before v1.0 protocol finalization.

## RFC Team Action Required

Please review and provide guidance on:

1. Correct interpretation of Matrix username format requirements
2. Whether the current User model validation aligns with PROTO.md
3. Any protocol clarifications needed for test data formats

## Files to Review

- `app/models/user.rb`
- `test/controllers/api/v1/*_controller_test.rb`
- `docs/PROTO.md` Sections 4.1, 4.2, 4.3

## Test Command to Reproduce

```bash
rails test test/controllers/api/v1/payments_controller_test.rb
```