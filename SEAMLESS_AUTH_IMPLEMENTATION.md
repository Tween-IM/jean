# Seamless Authentication Implementation

## Overview

This document describes the implementation of seamless authentication for TMCP mini-apps running in Element X, where users who are already logged into Matrix can use mini-apps without additional authentication prompts.

## Protocol Compliance

The TMCP Protocol (PROTO.md) specifies:

1. **Dual-Token Architecture** (Section 4.1):
   - TEP Token: Long-lived JWT for TMCP operations
   - MAS Access Token: Short-lived opaque token for Matrix operations
   - Separation of concerns for security

2. **Matrix Token Exchange** (Section 4.7.1):
   - Support for `urn:ietf:params:oauth:grant-type:reverse_1` grant type
   - MAS client registration with token exchange capabilities

3. **Auto-Provisioning** (Section 4.10):
   - User records automatically created from Matrix authentication
   - No pre-registration required

## Implementation Changes

### 1. New OAuth Grant Type: `matrix_token_exchange`

**Location:** `app/controllers/api/v1/oauth_controller.rb`

**Grant Type:** `urn:ietf:params:oauth:grant-type:matrix_token_exchange`

**Purpose:** Allows mini-apps with existing Matrix access tokens to exchange them for TEP tokens without user interaction.

#### Request

```http
POST /api/v1/oauth/token
Content-Type: application/x-www-form-urlencoded

grant_type=urn:ietf:params:oauth:grant-type:matrix_token_exchange
&matrix_access_token=<matrix_access_token_from_element>
&client_id=ma_your_app_001
&client_secret=<your_client_secret>
&scope=wallet:pay wallet:balance
&miniapp_context={"launch_source":"chat_bubble","room_id":"!abc123:tween.example"}
```

#### Response

```json
{
  "access_token": "tep.eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "Bearer",
  "expires_in": 86400,
  "refresh_token": "rt_abc123...",
  "scope": "wallet:pay wallet:balance",
  "user_id": "@alice:tween.example",
  "wallet_id": "tw_alice_123",
  "mas_access_token": "syt_abc123..."
}
```

### 2. Fixed Authorization Code Flow

**Changes:**
- Removed hardcoded user IDs (`@authenticated_user:tween.example`)
- Now validates Matrix access token with MAS before issuing TEP
- Calls MAS introspection endpoint to verify user
- Auto-creates User records from Matrix authentication

### 3. Auto-Provisioning from Matrix

**Implementation:**
```ruby
user = User.find_or_create_by(matrix_user_id: matrix_user_id) do |u|
  username_homeserver = matrix_user_id.split("@").last
  localpart, domain = username_homeserver.split(":")
  u.matrix_username = localpart
  u.matrix_homeserver = domain
end
```

**Benefits:**
- First-time users automatically provisioned from Matrix login
- No separate user registration required
- Matrix identity is source of truth

### 4. Enhanced Token Response

**Location:** `app/services/mas_client_service.rb`

**Changes:**
- Includes `mas_access_token` in response
- Adds `approval_history` claim to TEP token
- Adds `authorization_context` claim to TEP token
- Complete TEP claims as per PROTO.md Section 4.4

## Integration Flow for TweenPay Wallet App

### Step 1: User Launches TweenPay from Element X

User is already logged into Element X with Matrix access token.

### Step 2: TweenPay Requests TEP Token

```javascript
// TweenPay app code
const matrixAccessToken = elementX.getMatrixAccessToken();

const response = await fetch('/api/v1/oauth/token', {
  method: 'POST',
  headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
  body: new URLSearchParams({
    grant_type: 'urn:ietf:params:oauth:grant-type:matrix_token_exchange',
    matrix_access_token: matrixAccessToken,
    client_id: 'ma_tweenpay_001',
    client_secret: 'your_client_secret',
    scope: 'wallet:pay wallet:balance'
  })
});

const { access_token, user_id, wallet_id } = await response.json();
// Store TEP token in Keychain
secureStore.set('tep_token', access_token);
```

### Step 3: TMCP Server Validates Matrix Token

```ruby
# In OAuth controller
mas_client = MasClientService.new(...)
mas_user_info = mas_client.get_user_info(matrix_access_token)
# Calls MAS introspection endpoint
# Returns: { active: true, sub: "@alice:tween.example", ... }
```

### Step 4: Auto-Provisioning

```ruby
# If user doesn't exist in TMCP database
user = User.find_or_create_by(matrix_user_id: matrix_user_id) do |u|
  u.matrix_username = "alice"
  u.matrix_homeserver = "tween.example"
end

# User record automatically created
# wallet_id auto-generated
```

### Step 5: TEP Token Issued

```ruby
tep_response = mas_client.exchange_matrix_token_for_tep(
  matrix_access_token,
  client_id,
  scopes,
  miniapp_context
)

# Returns complete response with both tokens
{
  access_token: "tep.eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  mas_access_token: "syt_abc123...",  // Included for Matrix operations
  user_id: "@alice:tween.example",
  wallet_id: "tw_alice_123"
}
```

### Step 6: Use TEP Token

```javascript
// Now TweenPay can use TEP token for TMCP operations
const balance = await fetch('/api/v1/wallet/balance', {
  headers: {
    'Authorization': `Bearer ${tepToken}`
  }
});

// No additional login required - seamless experience!
```

## Security Features

### Client Secret Validation
- Mini-app client secret validated against Doorkeeper application
- Prevents unauthorized token exchange

### Matrix Token Validation
- All Matrix access tokens validated with MAS introspection
- Ensures token is active and valid
- Prevents token replay attacks

### Token Binding
- TEP token claims bind to specific mini-app (aud, azp)
- TEP tokens scoped to authorized permissions
- Cannot be reused by other applications

### User Auto-Provisioning Security
- Only creates users from valid Matrix authentication
- Matrix identity is source of truth
- Cannot forge user IDs without Matrix auth

## Configuration

### Environment Variables

```bash
# MAS Configuration
MAS_TOKEN_URL=https://mas.tween.example/oauth2/token
MAS_INTROSPECTION_URL=https://mas.tween.example/oauth2/introspect

# Optional: For TMCP server's own client credentials
MAS_CLIENT_SECRET=your_client_secret

# TMCP Configuration
TMCP_PRIVATE_KEY=your_rsa_private_key
TMCP_JWT_ISSUER=https://tmcp.tween.example
```

### Doorkeeper Application Registration

Each mini-app must be registered in Doorkeeper:

```ruby
Doorkeeper::Application.create!(
  name: "TweenPay Wallet",
  uid: "ma_tweenpay_001",
  secret: Rails.env.test? ? "test_secret" : SecureRandom.hex(32),
  redirect_uri: "https://tweenpay.example.com/callback",
  scopes: "wallet:pay wallet:balance user:read"
)
```

## Testing

### Unit Tests

**Location:** `test/controllers/api/v1/oauth_controller_test.rb`

New tests added:
1. `test_should_exchange_matrix_access_token_for_TEP_token`
   - Tests successful matrix_token_exchange grant
   - Verifies TEP token format
   - Validates response includes all expected fields

2. `test_should_reject_invalid_matrix_token_in_token_exchange`
   - Tests MAS token validation
   - Verifies error responses for invalid tokens

3. `test_should_require_matrix_access_token_and_client_id_for_token_exchange`
   - Tests required parameters
   - Validates error messages

4. `test_authorization_code_flow_should_validate_matrix_token_with_MAS`
   - Tests authorization code flow with MAS integration
   - Verifies token validation

### Running Tests

```bash
# Run all OAuth controller tests
rails test test/controllers/api/v1/oauth_controller_test.rb

# Run specific test
rails test test/controllers/api/v1/oauth_controller_test.rb -n "test_should_exchange_matrix_access_token"
```

## Code Changes Summary

### Files Modified

1. **app/controllers/api/v1/oauth_controller.rb**
   - Added `matrix_token_exchange` grant type handler
   - Fixed authorization code flow to use MAS validation
   - Added client secret validation
   - Added user auto-provisioning

2. **app/services/mas_client_service.rb**
   - Enhanced `exchange_matrix_token_for_tep` to include complete claims
   - Added `mas_access_token` to response
   - Added helper methods for approval history and authorization context

3. **test/controllers/api/v1/oauth_controller_test.rb**
   - Added 4 new test cases
   - Fixed existing tests for new behavior

## Backward Compatibility

All existing OAuth flows remain unchanged:
- Device authorization grant (RFC 8628)
- Authorization code grant with PKCE
- Refresh token flow

New `matrix_token_exchange` grant is additive, not breaking.

## Next Steps

1. **Deploy MAS Integration**
   - Set up MAS instance
   - Configure TMCP server with MAS endpoints
   - Test MAS connectivity

2. **Update Element X Client**
   - Implement matrix_token_exchange flow in TMCP Bridge
   - Auto-exchange Matrix tokens when mini-apps launch

3. **Production Testing**
   - Test with real Matrix access tokens
   - Verify auto-provisioning flow
   - Monitor error rates

## Troubleshooting

### Common Issues

**Issue:** "Invalid client credentials"
- Verify Doorkeeper application exists
- Check client_secret matches application.secret
- Ensure application is active

**Issue:** "Matrix token does not contain valid user ID"
- Verify MAS introspection endpoint is accessible
- Check Matrix access token is valid
- Ensure MAS returns `sub` claim

**Issue:** User auto-provisioning not working
- Check User model validations
- Verify matrix_user_id format is `@localpart:domain`
- Check database connection

### Debug Logging

```ruby
# In OAuth controller
Rails.logger.info "Token exchange: client_id=#{client_id}, matrix_user_id=#{matrix_user_id}"

# In MasClientService
Rails.logger.info "MAS introspection: active=#{mas_user_info['active']}"
```

## References

- TMCP Protocol: `docs/PROTO.md` Section 4
- OAuth 2.0 RFC: https://datatracker.ietf.org/doc/html/rfc6749
- MAS Specification: Matrix Authentication Service documentation
