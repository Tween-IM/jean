# TMCP Protocol Issues Discovered

## Critical Issues

### 1. MAS Grant Type Mismatch

**Location:** PROTO.md Section 4.3.1 (lines 516-518, 609)

**Issue:** PROTO.md requires TMCP Server to support `urn:ietf:params:oauth:grant-type:token-exchange` grant type, but MAS (Matrix Authentication Service) does not support this grant type.

**Actual MAS Support:**
According to [MAS Documentation](https://element-hq.github.io/matrix-authentication-service/topics/authorization.html#supported-authorization-grants):

| Grant Type | Supported by MAS |
|------------|------------------|
| `authorization_code` | ✅ Yes |
| `refresh_token` | ✅ Yes |
| `client_credentials` | ✅ Yes |
| `urn:ietf:params:oauth:grant-type:device_code` | ✅ Yes |
| `urn:ietf:params:oauth:grant-type:token-exchange` | ❌ **NO** |

**Impact:**
- TMCP Server's `refresh_access_token_for_matrix()` attempts to use `token-exchange` grant
- This fails with `unsupported_grant_type` error from MAS
- Matrix access tokens cannot be refreshed, forcing clients to use short-lived 5-minute tokens

**Solution Options:**

**Option A:** Keep existing Matrix access token
- Don't attempt to refresh Matrix tokens
- Return the original Matrix access token from the subject_token
- Let mini-apps handle Matrix token refresh themselves using OAuth 2.0 Device Authorization Grant

**Option B:** Document the limitation
- Update PROTO.md to reflect that Matrix token refresh is not supported
- Specify that clients must use Matrix OAuth 2.0 flows for token renewal
- TMCP Server should act as a pass-through for Matrix tokens from MAS

**Current Implementation:** Option A (return original Matrix access token)

---

## Non-Critical Issues

### 2. TEP Token Decode Logic
The TEP token service properly strips the `tep.` prefix when decoding, which is correct behavior.

### 3. Allowed Hosts Configuration
Added `core.tween.im` and `wallet.tween.im` to allowed hosts in development environment.

---

## Recommendations for PROTO.md Updates

### Section 4.3.1 (Matrix Session Delegation)

**Update Required:**

Change from:
```markdown
| Parameter | Required | Description |
|-----------|-----------|-------------|
| `grant_types` | Yes | MUST include: `urn:ietf:params:oauth:grant-type:token-exchange`, `refresh_token` |
```

To:
```markdown
| Parameter | Required | Description |
|-----------|-----------|-------------|
| `grant_types` | Yes | MUST include: `authorization_code`, `device_code`, `refresh_token`, `client_credentials` |
```

**Add Note:**
> **NOTE:** MAS does not support `urn:ietf:params:oauth:grant-type:token-exchange` grant type. TMCP Server should return the original Matrix access token from the subject_token and not attempt token refresh. Clients are responsible for managing Matrix token lifecycle using MAS OAuth 2.0 flows.

---

## Date Discovered
January 16, 2026
