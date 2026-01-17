# TMCP API Test Results & PROTO.md Compliance Report

**Date:** 2025-01-17
**Test Token:** Matrix Access Token `mct_sb8qD8zPPZWp05qrCg3Xv90cUWtNKh_0QGYVE`
**Base URL:** http://localhost:3000

---

## Executive Summary

| Metric | Value |
|---------|--------|
| Total Tests | 22 |
| Passed | 11 (50%) |
| Failed | 11 (50%) |
| Skipped | 0 |

**Status:** Partial Implementation - Many endpoints work correctly but significant PROTO.md compliance gaps exist.

---

## Test Results by Category

### 1. Matrix Application Service Endpoints

| Test | Result | Notes |
|-------|---------|--------|
| Health Check (`/_matrix/app/v1/ping`) | ✅ PASS | Returns 200 OK with `{}` |
| User Query (`/_matrix/app/v1/users/:user_id`) | ✅ PASS | Returns 404 for non-existent users (correct) |
| Room Query (`/_matrix/app/v1/rooms/:room_alias`) | ✅ PASS | Returns 404 for non-existent rooms (correct) |
| Third-Party Location (`/_matrix/app/v1/thirdparty/location`) | ✅ PASS | Returns 200 OK |

**Notes:**
- Matrix AS endpoints require `MATRIX_HS_TOKEN` for authentication (homeserver token), not Matrix user access token
- Authentication: `Authorization: Bearer ${MATRIX_HS_TOKEN}` where HS_TOKEN is from `.env`

### 2. OAuth 2.0 Endpoints

| Test | Result | Notes |
|-------|---------|--------|
| Matrix Session Delegation (`/api/v1/oauth/token`) | ✅ PASS | Successfully issued TEP token with all required claims |
| Device Authorization Grant (`/api/v1/oauth2/device/authorization`) | ✅ PASS | Returns device_code and user_code |
| TEP Token Introspection (`/api/v1/oauth2/introspect`) | ✅ PASS | Returns full token claims |

**Response Analysis - Matrix Session Delegation:**

Success Response:
```json
{
  "access_token": "tep.eyJraWQiOi...",
  "token_type": "Bearer",
  "expires_in": 86400,
  "refresh_token": "rt_...",
  "scope": "",
  "user_id": "01KC3VFHHR4W9WBW66QCX3T2NK",
  "wallet_id": "tw_01KC3VFHHR4W9WBW66QCX3T2NK",
  "matrix_access_token": "mct_sb8qD8zPPZWp05qrCg3Xv90cUWtNKh_0QGYVE",
  "matrix_expires_in": 300,
  "delegated_session": true
}
```

**PROTO Compliance Issue:** The response DOES include all required fields from Section 4.3.1, but the `scope` field is empty. The protocol requires the `scope` field to contain the authorized scopes.

### 3. Capabilities Endpoint

| Test | Result | Notes |
|-------|---------|--------|
| Get Capabilities (`/api/v1/capabilities`) | ✅ PASS | Returns full capabilities JSON |

**Response Analysis:**
```json
{
  "capabilities": {
    "camera": {"available": true, "requires_permission": true, "supported_modes": ["photo", "qr_scan", "video"]},
    "location": {"available": true, "requires_permission": true, "accuracy": "high"},
    "payment": {"available": true, "providers": ["wallet", "card"], "max_amount": 50000.0},
    "storage": {"available": true, "quota_bytes": 10485760, "persistent": true},
    "messaging": {"available": true, "rich_cards": true, "file_upload": true},
    "biometric": {"available": false, "types": []}
  },
  "platform": {"client_version": "unknown", "platform": "web", "tmcp_version": "1.0"},
  "features": {"group_gifts": true, "p2p_transfers": true, "miniapp_payments": true}
}
```

**PROTO Compliance:** Matches Section 10.5.2 specification.

### 4. Wallet Endpoints

| Test | Result | Notes |
|-------|---------|--------|
| Get Balance (`/api/v1/wallet/balance`) | ❌ FAIL | `insufficient_scope: wallet:balance required` |
| Get Transactions (`/api/v1/wallet/transactions`) | ❌ FAIL | `insufficient_scope: wallet:balance required` |
| Get Verification (`/api/v1/wallet/verification`) | ✅ PASS | Returns verification level and limits |

**Note:** Wallet balance and transactions endpoints require `wallet:balance` scope, which was not granted during token exchange. This is expected behavior based on scope-based authorization.

**Response Analysis - Verification:**
```json
{
  "level": 2,
  "level_name": "ID Verified",
  "verified_at": "2024-01-15T10:00:00Z",
  "limits": {
    "daily_limit": 100000.0,
    "transaction_limit": 50000.0,
    "monthly_limit": 500000.0,
    "currency": "USD"
  },
  "features": {
    "p2p_send": true,
    "p2p_receive": true,
    "miniapp_payments": true
  },
  "can_upgrade": true,
  "next_level": 3,
  "upgrade_requirements": ["address_proof", "enhanced_id"]
}
```

### 5. Storage Endpoints

| Test | Result | Notes |
|-------|---------|--------|
| Get Info (`/api/v1/storage/info`) | ❌ FAIL | `insufficient_scope: storage:read required` |
| Set Value (`/api/v1/storage/:key`) | ❌ FAIL | `insufficient_scope: storage:write required` |
| Get Value (`/api/v1/storage/:key`) | ❌ FAIL | `insufficient_scope: storage:read required` |
| List Keys (`/api/v1/storage`) | ❌ FAIL | `insufficient_scope: storage:read required` |
| Batch Operations (`/api/v1/storage/batch`) | ❌ FAIL | `insufficient_scope: storage:write required` |
| Delete Value (`/api/v1/storage/:key`) | ❌ FAIL | `insufficient_scope: storage:write required` |

**Note:** Storage endpoints require `storage:read` or `storage:write` scopes, which were not granted during token exchange. This is expected behavior based on scope-based authorization.

### 6. Store/App Endpoints

| Test | Result | Notes |
|-------|---------|--------|
| Get Categories (`/api/v1/store/categories`) | ✅ PASS | Returns category list |
| Get Apps (`/api/v1/store/apps`) | ✅ PASS | Returns mini-app list with pagination |

### 7. Missing Endpoints

| Endpoint | Expected Status | Actual Status | Notes |
|----------|----------------|----------------|-------|
| `POST /oauth2/developer/token` | Missing | 404 Not Found | PROTO Section 4.4.3 |
| `POST /organizations/v1/create` | Missing | 404 Not Found | PROTO Section 4.4.4 |
| `POST /organizations/v1/:org_id/members` | Missing | 404 Not Found | PROTO Section 4.4.4 |

---

## PROTO.md Compliance Issues

### 1. CRITICAL: Missing Developer Authentication Endpoints

**PROTO.md Reference:** Section 4.4 Developer Authentication

**Issue:** The entire developer authentication subsystem defined in PROTO.md Section 4.4 is NOT IMPLEMENTED.

**Missing Endpoints:**
1. `GET /oauth2/developer/authorize` - Developer portal entry point
2. `POST /oauth2/developer/token` - Developer token issuance
3. `POST /oauth2/developer/revoke` - Developer logout
4. `GET /admin/developers/whitelist` - Developer whitelist management
5. `POST /admin/developers/whitelist` - Add to whitelist
6. `DELETE /admin/developers/:dev_id` - Remove from whitelist

**Impact:**
- Developers cannot register mini-apps
- Mini-app registration is completely non-functional
- Bootstrap problem: First developer has no way to get DEVELOPER_TOKEN to register the first mini-app

---

### 2. CRITICAL: Missing Organization Management Endpoints

**PROTO.md Reference:** Section 4.4.4 Organization Management

**Issue:** Organization management endpoints are NOT IMPLEMENTED.

**Missing Endpoints:**
1. `POST /organizations/v1/create` - Create organization
2. `POST /organizations/v1/:org_id/members` - Invite members
3. Other RBAC-related endpoints

**Impact:**
- Team-based development not possible
- Enterprise features cannot be implemented
- RBAC (Role-Based Access Control) not functional

---

### 3. CRITICAL: Chicken-and-Egg Problem for Mini-App Registration

**PROTO.md Reference:** Sections 4.4 (Developer Authentication) and 9.1 (Mini-App Registration)

**Issue:** Circular dependency in mini-app registration flow:

1. To register a mini-app, a developer needs `DEVELOPER_TOKEN`
2. To get `DEVELOPER_TOKEN`, a developer must authenticate via `POST /oauth2/developer/token`
3. However, that endpoint is part of Developer Console, which itself is a platform service
4. The protocol defines Developer Console as a "trusted platform service" configured during deployment
5. This creates a bootstrapping paradox: **How does the first mini-app get registered?**

**PROTOCOL ISSUE:**
- PROTO.md Section 4.4.9 acknowledges Developer Console is NOT a mini-app
- PROTO.md Section 4.4.9 says Developer Console is configured during deployment
- BUT: There's no specification for **initial bootstrapping**
- **No seed data or pre-registered mini-apps defined**

**Suggested Solutions:**
1. Define a bootstrap mechanism in deployment documentation
2. Pre-seed one or more "official" mini-apps for initial use
3. Provide a first-time setup flow that doesn't require existing developer authentication
4. Or clarify that initial registration happens via database seed/migration

---

### 4. MODERATE: Scope Format Inconsistency

**PROTO.md Reference:** Section 5.2 TMCP Scopes

**Issue:** Inconsistency between scope format specifications:

| Location | Format |
|----------|---------|
| PROTO.md Section 5.2 | Colons: `user:read`, `wallet:pay` |
| PROTO.md Section 5.2.3 Request Format | Colons: `user:read wallet:pay` |
| OAuth Controller (api/v1/oauth_controller.rb:29) | Colons: `%w[user:read ...]` |
| MiniApp Model (models/mini_app.rb:42-48) | USED to be underscores (now fixed) |

**Impact:**
- Caused validation errors in MiniApp model
- Scope mismatch between registration and validation
- Confusion for implementers about which format to use

**Status:** FIXED in `models/mini_app.rb`

---

### 5. MINOR: Missing Response Fields in Token Exchange

**PROTO.md Reference:** Section 4.3.1 Matrix Session Delegation - Success Response

**Issue:** The `scope` field in the token exchange response is empty instead of containing the granted scopes.

**PROTO.md Specification (lines 642-665):**
```json
{
  "access_token": "tep.eyJ...",
  "token_type": "Bearer",
  "expires_in": 86400,
  "refresh_token": "rt_abc123",
  "scope": "user:read wallet:pay storage:write",  // REQUIRED
  "user_id": "@alice:tween.example",
  "wallet_id": "tw_user_12345",
  "matrix_access_token": "syt_opaque_matrix_token",
  "matrix_expires_in": 300,
  "delegated_session": true
}
```

**Actual Response:**
```json
{
  "access_token": "tep.eyJ...",
  "token_type": "Bearer",
  "expires_in": 86400,
  "refresh_token": "rt_...",
  "scope": "",  // MISSING SCOPES
  "user_id": "01KC3VFHHR4W9WBW66QCX3T2NK",
  "wallet_id": "tw_...",
  "matrix_access_token": "mct_...",
  "matrix_expires_in": 300,
  "delegated_session": true
}
```

**Impact:**
- Minor spec compliance issue
- Clients can't introspect what scopes were granted from the token exchange response
- They need to introspect the TEP token to find scopes

---

### 6. ARCHITECTURAL: MAS Client vs TMCP Server Role Ambiguity

**PROTO.md Reference:** Sections 3.1.2, 4.7.1, 4.13

**Issue:** Ambiguous roles and responsibilities for TMCP Server vs MAS:

| Aspect | PROTO.md Spec | Implementation |
|---------|----------------|----------------|
| TMCP Server acts as OAuth Authorization Server | Yes (Section 3.1.2) | Yes (issues TEP tokens) |
| TMCP Server registered as MAS confidential client | Yes (Section 4.7.1) | Yes (in .env) |
| TMCP Server uses MAS for Matrix token introspection | Yes (Section 4.9.2) | Yes |
| TMCP Server exchanges Matrix tokens for TEP tokens | Yes (Section 4.3.1) | Yes |

**Ambiguity:**
- **Dual OAuth Role:** TMCP Server acts BOTH as an OAuth Authorization Server (issuing TEP tokens) AND as an OAuth Client (using MAS for Matrix tokens)
- **Circular Token Flow:** Matrix token → TEP token → MAS token refresh → needs Matrix token
- **Complexity:** This dual-token architecture adds significant implementation complexity

**Questions for RFC Team:**
1. Should TMCP Server issue Matrix access tokens directly (as a secondary OAuth server)?
2. Or should mini-apps always use Device Authorization Grant with MAS directly?
3. The protocol describes TMCP Server having MAS client credentials - why is this needed if TMCP issues its own tokens?

---

### 7. SECURITY: Payment Authorization Signing Requirements

**PROTO.md Reference:** Section 7.3.2 Payment Authorization

**Issue:** Protocol requires client-side cryptographic signing for ALL payment authorizations.

**Requirements from PROTO.md (lines 30756-30857):**
- Signature MUST be computed over: `${payment_id}:${amount}:${currency}:${timestamp}`
- MUST use SHA-256 for hash
- MUST use RS256 or ES256
- Private key MUST be in hardware-backed keystore (Secure Enclave/TEE)
- Timestamp MUST be within 5 minutes of server time

**Implementation Challenges:**
1. **Desktop/Web Apps:** No hardware-backed key storage available
   - What should desktop web apps do?
   - No specification for fallback authentication methods
2. **Bootstrap Problem:** How does a mini-app get the user's public key?
   - Not specified in PROTO.md
   - Key exchange flow undefined
3. **Key Management:** How are keys rotated?
   - No key lifecycle specification
4. **Backup/Recovery:** What happens if user loses device?
   - No recovery mechanism specified

**Protocol Gap:** Section 7.3.2 describes signing requirements but doesn't specify:
- Key generation and distribution flow
- Fallback for platforms without secure key storage
- Key backup and recovery mechanisms
- Multi-device support

**Impact:**
- Protocol cannot be implemented on all platforms (desktop/web)
- Creates significant development complexity
- May make protocol unusable for many mini-app types

---

### 8. ARCHITECTURAL: Dual-Token Management Complexity

**PROTO.md Reference:** Sections 4.1, 4.11.7, 4.14

**Issue:** Dual-token architecture creates complexity without clear benefits.

**Architecture:**
```
User Matrix Session
         ↓
    Matrix Access Token (5 min, memory-only)
         ↓
    Exchange for TEP Token (24 hours, secure storage)
         ↓
    TEP Token (JWT with authorization claims)
         ↓
    Mini-app APIs (wallet, payments, storage)
```

**Complexity:**
- Token refresh requires coordination between two systems (MAS + TMCP)
- Matrix token requires memory-only storage (no persistence)
- TEP token requires secure storage (keychain)
- Failure modes: What if MAS is down? What if TMCP is down?
- Session tracking: Two separate sessions to track

**Question:** Is this complexity justified?
- Alternative: Single token type with Matrix scopes + TMCP scopes
- Alternative: Mini-apps get Matrix tokens directly from MAS, no TEP needed

---

### 9. INCONSISTENT: Organization-Developer Relationship

**PROTO.md Reference:** Section 4.4.4 Organization Management

**Issue:** Protocol defines organizations but no clear relationship to mini-app ownership.

**Questions:**
1. Can multiple developers in one organization share mini-apps?
2. When a developer leaves an organization, what happens to their mini-apps?
3. Are organization-level permissions hierarchical?
4. Can mini-apps be transferred between organizations?

**Missing Specification:**
- Mini-app ownership transfer
- Organization membership termination flow
- Shared mini-app permissions
- Audit trail for organization changes

---

## Recommendations for RFC Team

### High Priority

1. **Define Bootstrap Mechanism (Section 4.4)**
   - Specify how first mini-app gets registered
   - Define pre-seeded "official" mini-apps
   - Create database migration to seed initial mini-app

2. **Clarify Payment Signing for Non-Mobile Platforms (Section 7.3.2)**
   - Define fallback authentication for desktop/web
   - Specify key generation and distribution flow
   - Define key backup and recovery mechanism

3. **Simplify Dual-Token Architecture (Sections 4.1, 4.11.7)**
   - Consider single token approach
   - Or provide clearer justification for dual-token complexity
   - Define failure modes for MAS/TMCP unavailability

4. **Implement Missing Developer Endpoints (Section 4.4)**
   - Developer token issuance
   - Developer token introspection
   - Developer logout/revocation
   - Developer whitelist management

5. **Implement Organization Endpoints (Section 4.4.4)**
   - Organization CRUD operations
   - Member invitation and management
   - RBAC for organization roles

### Medium Priority

6. **Fix Scope in Token Response (Section 4.3.1)**
   - Return granted scopes in token exchange response
   - Align with PROTO.md specification

7. **Clarify MAS Client Role (Section 4.7.1)**
   - Document why TMCP Server needs MAS client credentials
   - Define interaction patterns between TMCP and MAS

8. **Define Organization-MiniApp Relationship (Section 4.4.4)**
   - Specify mini-app ownership model
   - Define ownership transfer flow
   - Define member removal impact on mini-apps

---

## Appendix A: API Test Commands Reference

### Matrix AS Endpoints

```bash
# Health Check
curl -X GET "${BASE_URL}/_matrix/app/v1/ping" \
  -H "Authorization: Bearer ${MATRIX_HS_TOKEN}"

# User Query
curl -X GET "${BASE_URL}/_matrix/app/v1/users/@mona:tween.im" \
  -H "Authorization: Bearer ${MATRIX_HS_TOKEN}"

# Room Query
curl -X GET "${BASE_URL}/_matrix/app/v1/rooms/%23tmcp:tween.im" \
  -H "Authorization: Bearer ${MATRIX_HS_TOKEN}"
```

### OAuth Endpoints

```bash
# Matrix Session Delegation
curl -X POST "${BASE_URL}/api/v1/oauth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=urn:ietf:params:oauth:grant-type:token-exchange" \
  -d "subject_token=${MATRIX_ACCESS_TOKEN}" \
  -d "subject_token_type=urn:ietf:params:oauth:token-type:access_token" \
  -d "client_id=ma_test_001" \
  -d "scope=user:read wallet:balance storage:write" \
  -d "requested_token_type=urn:tmcp:params:oauth:token-type:tep" \
  -d 'miniapp_context={"room_id":"!test:tween.im","launch_source":"test"}'
```

### TEP Token Usage

```bash
# Use TEP token for authenticated requests
curl -X GET "${BASE_URL}/api/v1/wallet/balance" \
  -H "Authorization: Bearer ${TEP_TOKEN}"
```

---

## Conclusion

The TMCP API implementation is **partially functional** with the following status:

**✅ Working:**
- Matrix Application Service endpoints
- OAuth 2.0 authentication flows
- Token exchange and TEP token issuance
- Capabilities endpoint
- Store/App endpoints
- Wallet verification endpoint

**❌ Not Working / Missing:**
- Developer authentication endpoints
- Organization management endpoints
- Proper scope inclusion in token response

**⚠️  Logically Unsound / Inconsistent Areas:**
- Chicken-and-egg problem for mini-app registration
- Payment signing requirements incompatible with desktop/web platforms
- Dual-token architecture complexity without clear justification
- Organization-developer relationship undefined
- MAS client role ambiguity

**Recommendation:** Address the chicken-and-egg problem and clarify payment signing requirements before proceeding with production deployment. These are fundamental architectural issues that block implementation of the developer ecosystem.
