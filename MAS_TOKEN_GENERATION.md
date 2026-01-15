# Generating MAS Tokens for Matrix Authentication

Since you have a Matrix login, you can generate MAS tokens using the OAuth 2.0 flows supported by Matrix Authentication Service (MAS).

## Available MAS Token Flows

### 1. Device Authorization Grant (Recommended for Testing)

This is the easiest flow for testing - no browser redirect needed.

#### Step 1: Request Device Authorization
```bash
curl -X POST https://auth.tween.im/oauth2/device/authorization \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=tmcp-server&scope=urn:matrix:org.matrix.msc2967.client:api:*"
```

**Response:**
```json
{
  "device_code": "GmRhmhcxhwAzkoEqiMEg_DnyEysNkuNhszIySk9eS",
  "user_code": "WDJB-MJHR",
  "verification_uri": "https://auth.tween.im/oauth2/device",
  "verification_uri_complete": "https://auth.tween.im/oauth2/device?user_code=WDJB-MJHR",
  "expires_in": 900,
  "interval": 5
}
```

#### Step 2: Complete Authorization
1. Open `verification_uri` in your browser: `https://auth.tween.im/oauth2/device`
2. Enter the `user_code`: `WDJB-MJHR`
3. Login with your Matrix credentials if prompted
4. Approve the authorization

#### Step 3: Poll for Token
```bash
# Wait a few seconds, then poll for the token
curl -X POST https://auth.tween.im/oauth2/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=urn:ietf:params:oauth:grant-type:device_code&device_code=GmRhmhcxhwAzkoEqiMEg_DnyEysNkuNhszIySk9eS&client_id=tmcp-server"
```

**Success Response:**
```json
{
  "access_token": "syt_matrix_access_token_here",
  "token_type": "Bearer",
  "expires_in": 3600,
  "refresh_token": "refresh_token_here",
  "scope": "urn:matrix:org.matrix.msc2967.client:api:*"
}
```

### 2. Authorization Code Grant (For Web Applications)

#### Step 1: Get Authorization Code
```bash
# This would typically be done in a browser, but for testing:
curl -X GET "https://auth.tween.im/oauth2/authorize?response_type=code&client_id=tmcp-server&scope=urn:matrix:org.matrix.msc2967.client:api:*&redirect_uri=https://tmcp.tween.im/callback"
```

**Follow the browser flow to get the authorization code.**

#### Step 2: Exchange Code for Token
```bash
curl -X POST https://auth.tween.im/oauth2/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -u "tmcp-server:YOUR_CLIENT_SECRET" \
  -d "grant_type=authorization_code&code=YOUR_AUTH_CODE&redirect_uri=https://tmcp.tween.im/callback"
```

### 3. Refresh Token Flow (If you have a refresh token)

```bash
curl -X POST https://auth.tween.im/oauth2/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -u "tmcp-server:YOUR_CLIENT_SECRET" \
  -d "grant_type=refresh_token&refresh_token=YOUR_REFRESH_TOKEN"
```

## Testing MAS Token with TMCP Server

Once you have the MAS token, test Matrix Session Delegation:

```bash
# Replace YOUR_MATRIX_TOKEN with the access_token from MAS
curl -X POST http://localhost:3000/api/v1/oauth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=urn:ietf:params:oauth:grant-type:token-exchange&subject_token=YOUR_MATRIX_TOKEN&subject_token_type=urn:ietf:params:oauth:token-type:access_token&client_id=ma_tweenpay&scope=user:read wallet:balance"
```

**Expected Response:**
```json
{
  "access_token": "tep.eyJhbGciOiJSUzI1NiIs...",
  "token_type": "Bearer",
  "expires_in": 86400,
  "matrix_access_token": "syt_new_matrix_token",
  "user_id": "@your_username:tween.im",
  "wallet_id": "tw_your_wallet_id",
  "delegated_session": true
}
```

## MAS Token Validation

You can validate any MAS token using introspection:

```bash
curl -X POST https://auth.tween.im/oauth2/introspect \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -u "tmcp-server:YOUR_CLIENT_SECRET" \
  -d "token=YOUR_MATRIX_TOKEN"
```

## Quick Test Script

Run the demo script to see the complete flow:

```bash
./demo-matrix-delegation.sh
```

This will:
1. Get a test Matrix token from MAS
2. Introspect it to verify validity
3. Show the delegation request format
4. Demonstrate the complete authentication flow

## Summary

To get a MAS token with your Matrix login:

1. **Use Device Authorization Grant** (easiest for testing)
2. **Complete the browser authorization flow**
3. **Exchange the device code for tokens**
4. **Use the access_token for Matrix Session Delegation**

The MAS token enables seamless mini-app authentication without additional logins!