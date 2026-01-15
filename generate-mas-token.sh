#!/bin/bash
# MAS Token Generation Script
# Generates Matrix access tokens using Device Authorization Grant

set -e

# Configuration
MAS_SERVER="http://docker:8080"
CLIENT_ID="tmcp-server"
CLIENT_SECRET="pF/Y9eiJXTHASLFNPOIzXiym0E9o1J7o5+UsHONumS0="

echo "=== MAS Token Generation ==="
echo "MAS Server: $MAS_SERVER"
echo "Client ID: $CLIENT_ID"
echo

# Step 1: Request device authorization
echo "Step 1: Requesting device authorization..."
DEVICE_RESPONSE=$(curl -s -X POST "$MAS_SERVER/oauth2/device/authorization" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=$CLIENT_ID&scope=urn:matrix:org.matrix.msc2967.client:api:*")

echo "Device authorization response:"
echo "$DEVICE_RESPONSE" | jq .
echo

# Extract values
DEVICE_CODE=$(echo "$DEVICE_RESPONSE" | jq -r '.device_code')
USER_CODE=$(echo "$DEVICE_RESPONSE" | jq -r '.user_code')
VERIFICATION_URI=$(echo "$DEVICE_RESPONSE" | jq -r '.verification_uri')
EXPIRES_IN=$(echo "$DEVICE_RESPONSE" | jq -r '.expires_in')

if [ -z "$DEVICE_CODE" ] || [ "$DEVICE_CODE" = "null" ]; then
  echo "❌ Failed to get device code"
  exit 1
fi

echo "✅ Device code obtained: $DEVICE_CODE"
echo "📱 User code: $USER_CODE"
echo "🔗 Verification URL: $VERIFICATION_URI"
echo
echo "📋 Instructions:"
echo "1. Open this URL in your browser: $VERIFICATION_URI"
echo "2. Enter the user code: $USER_CODE"
echo "3. Login with your Matrix credentials and approve"
echo "4. Return here and press Enter to continue..."
echo

read -p "Press Enter after completing authorization in browser..."

# Step 2: Poll for token
echo "Step 2: Polling for access token..."
echo "(This may take a few seconds...)"

MAX_ATTEMPTS=60  # 5 minutes max
ATTEMPT=1

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
  echo -n "Attempt $ATTEMPT/$MAX_ATTEMPTS... "

  TOKEN_RESPONSE=$(curl -s -X POST "$MAS_SERVER/oauth2/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=urn:ietf:params:oauth:grant-type:device_code&device_code=$DEVICE_CODE&client_id=$CLIENT_ID")

  # Check if we got a token
  ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
  ERROR=$(echo "$TOKEN_RESPONSE" | jq -r '.error')

  if [ -n "$ACCESS_TOKEN" ] && [ "$ACCESS_TOKEN" != "null" ]; then
    echo "✅ Success!"
    echo
    echo "=== MAS Token Obtained ==="
    echo "Access Token: $ACCESS_TOKEN"
    echo "Token Type: $(echo "$TOKEN_RESPONSE" | jq -r '.token_type')"
    echo "Expires In: $(echo "$TOKEN_RESPONSE" | jq -r '.expires_in') seconds"
    echo "Refresh Token: $(echo "$TOKEN_RESPONSE" | jq -r '.refresh_token')"
    echo "Scope: $(echo "$TOKEN_RESPONSE" | jq -r '.scope')"
    echo

    # Test the token with introspection
    echo "Testing token with MAS introspection..."
    INTROSPECTION=$(curl -s -X POST "$MAS_SERVER/oauth2/introspect" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -u "$CLIENT_ID:$CLIENT_SECRET" \
      -d "token=$ACCESS_TOKEN")

    echo "Introspection result:"
    echo "$INTROSPECTION" | jq .
    echo

    USER_ID=$(echo "$INTROSPECTION" | jq -r '.sub')
    ACTIVE=$(echo "$INTROSPECTION" | jq -r '.active')

    if [ "$ACTIVE" = "true" ]; then
      echo "✅ Token is valid for user: $USER_ID"
      echo
      echo "=== Ready for Matrix Session Delegation ==="
      echo "Use this Matrix token in TMCP Server delegation:"
      echo
      echo "curl -X POST http://localhost:3000/api/v1/oauth/token \\"
      echo "  -H \"Content-Type: application/x-www-form-urlencoded\" \\"
      echo "  -d \"grant_type=urn:ietf:params:oauth:grant-type:token-exchange&subject_token=$ACCESS_TOKEN&subject_token_type=urn:ietf:params:oauth:token-type:access_token&client_id=ma_tweenpay&scope=user:read wallet:balance\""
      echo
      echo "🎉 MAS token generation complete!"
    else
      echo "❌ Token validation failed"
    fi

    exit 0
  fi

  if [ "$ERROR" = "authorization_pending" ]; then
    echo "Waiting for authorization..."
    sleep 5
  elif [ "$ERROR" = "slow_down" ]; then
    echo "Slow down requested, waiting longer..."
    sleep 10
  else
    echo "Error: $ERROR"
    echo "Response: $TOKEN_RESPONSE"
    exit 1
  fi

  ATTEMPT=$((ATTEMPT + 1))
done

echo "❌ Timeout waiting for authorization"
echo "The device code may have expired. Try again."
exit 1