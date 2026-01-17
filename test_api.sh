#!/bin/bash

# TMCP API Comprehensive Test Script
# Tests all API endpoints starting from authentication

MATRIX_ACCESS_TOKEN="mct_sb8qD8zPPZWp05qrCg3Xv90cUWtNKh_0QGYVE"
BASE_URL="http://localhost:3000"
MATRIX_HS_TOKEN="874542cda496ffd03f8fd283ad37d8837572aad0734e92225c5f7fffd8c91bd1"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
PASSED=0
FAILED=0
TOTAL=0

log_test() {
    TOTAL=$((TOTAL + 1))
    local test_name="$1"
    local result="$2"

    if [ "$result" = "PASS" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $test_name"
        FAILED=$((FAILED + 1))
    fi
}

print_section() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

# Store tokens
TEP_TOKEN=""
REFRESH_TOKEN=""

# ============================================================================
# SECTION 1: Matrix Application Service Endpoints
# ============================================================================
print_section "1. Testing Matrix Application Service Endpoints"

# 1.1 Health Check (Ping)
echo "1.1 Testing /_matrix/app/v1/ping (Health Check)"
PING_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/_matrix/app/v1/ping" \
  -H "Authorization: Bearer ${MATRIX_HS_TOKEN}")
PING_CODE=$(echo "$PING_RESPONSE" | tail -n1)
PING_BODY=$(echo "$PING_RESPONSE" | head -n-1)
echo "Response Code: $PING_CODE"
echo "Response Body: $PING_BODY"
if [ "$PING_CODE" = "200" ]; then
    log_test "Matrix AS Health Check" "PASS"
else
    log_test "Matrix AS Health Check" "FAIL"
fi

# 1.2 User Query
echo -e "\n1.2 Testing /_matrix/app/v1/users/:user_id (User Query)"
USER_QUERY_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/_matrix/app/v1/users/@mona:tween.im" \
  -H "Authorization: Bearer ${MATRIX_HS_TOKEN}")
USER_QUERY_CODE=$(echo "$USER_QUERY_RESPONSE" | tail -n1)
USER_QUERY_BODY=$(echo "$USER_QUERY_RESPONSE" | head -n-1)
echo "Response Code: $USER_QUERY_CODE"
echo "Response Body: $USER_QUERY_BODY"
if [ "$USER_QUERY_CODE" = "200" ]; then
    log_test "Matrix AS User Query" "PASS"
else
    log_test "Matrix AS User Query" "FAIL"
fi

# 1.3 Room Query
echo -e "\n1.3 Testing /_matrix/app/v1/rooms/:room_alias (Room Query)"
ROOM_QUERY_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/_matrix/app/v1/rooms/#tmcp:Tween" \
  -H "Authorization: Bearer ${MATRIX_HS_TOKEN}")
ROOM_QUERY_CODE=$(echo "$ROOM_QUERY_RESPONSE" | tail -n1)
ROOM_QUERY_BODY=$(echo "$ROOM_QUERY_RESPONSE" | head -n-1)
echo "Response Code: $ROOM_QUERY_CODE"
echo "Response Body: $ROOM_QUERY_BODY"
# Note: Room query might return 404 if room doesn't exist, which is acceptable

# 1.4 Third-Party Protocol Endpoints
echo -e "\n1.4 Testing Third-Party Location Endpoint"
TP_LOCATION_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/_matrix/app/v1/thirdparty/location")
TP_LOCATION_CODE=$(echo "$TP_LOCATION_RESPONSE" | tail -n1)
echo "Response Code: $TP_LOCATION_CODE"
if [ "$TP_LOCATION_CODE" = "200" ] || [ "$TP_LOCATION_CODE" = "404" ]; then
    log_test "Third-Party Location Endpoint" "PASS"
else
    log_test "Third-Party Location Endpoint" "FAIL"
fi

# ============================================================================
# SECTION 2: OAuth 2.0 Endpoints
# ============================================================================
print_section "2. Testing OAuth 2.0 Endpoints"

# 2.1 Matrix Session Delegation (Token Exchange)
echo "2.1 Testing Matrix Session Delegation (Token Exchange)"
echo "Requesting TEP token from Matrix access token..."
TOKEN_EXCHANGE_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/v1/oauth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=urn:ietf:params:oauth:grant-type:token-exchange" \
  -d "subject_token=${MATRIX_ACCESS_TOKEN}" \
  -d "subject_token_type=urn:ietf:params:oauth:token-type:access_token" \
  -d "client_id=ma_test_001" \
  -d "scope=user:read wallet:balance storage:write" \
  -d "requested_token_type=urn:tmcp:params:oauth:token-type:tep" \
  -d "miniapp_context=$(echo '{"room_id":"!test:tween.im","launch_source":"test"}' | jq -cRs)")

TOKEN_EXCHANGE_CODE=$(echo "$TOKEN_EXCHANGE_RESPONSE" | tail -n1)
TOKEN_EXCHANGE_BODY=$(echo "$TOKEN_EXCHANGE_RESPONSE" | head -n-1)
echo "Response Code: $TOKEN_EXCHANGE_CODE"
echo "Response Body: $TOKEN_EXCHANGE_BODY"

if [ "$TOKEN_EXCHANGE_CODE" = "200" ]; then
    log_test "Matrix Session Delegation" "PASS"
    TEP_TOKEN=$(echo "$TOKEN_EXCHANGE_BODY" | jq -r '.access_token // empty')
    REFRESH_TOKEN=$(echo "$TOKEN_EXCHANGE_BODY" | jq -r '.refresh_token // empty')
    USER_ID=$(echo "$TOKEN_EXCHANGE_BODY" | jq -r '.user_id // empty')
    WALLET_ID=$(echo "$TOKEN_EXCHANGE_BODY" | jq -r '.wallet_id // empty')
    echo -e "${GREEN}TEP Token obtained: ${TEP_TOKEN:0:50}...${NC}"
    echo -e "${GREEN}User ID: $USER_ID${NC}"
    echo -e "${GREEN}Wallet ID: $WALLET_ID${NC}"
else
    log_test "Matrix Session Delegation" "FAIL"
    echo -e "${YELLOW}Note: Continuing without TEP token - subsequent tests may fail${NC}"
fi

# 2.2 Token Introspection
echo -e "\n2.2 Testing Token Introspection"
if [ -n "$TEP_TOKEN" ]; then
    INTROSPECT_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/v1/oauth2/introspect" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "token=${TEP_TOKEN}")
    INTROSPECT_CODE=$(echo "$INTROSPECT_RESPONSE" | tail -n1)
    INTROSPECT_BODY=$(echo "$INTROSPECT_RESPONSE" | head -n-1)
    echo "Response Code: $INTROSPECT_CODE"
    echo "Response Body: $INTROSPECT_BODY"
    if [ "$INTROSPECT_CODE" = "200" ]; then
        ACTIVE=$(echo "$INTROSPECT_BODY" | jq -r '.active // false')
        if [ "$ACTIVE" = "true" ]; then
            log_test "Token Introspection" "PASS"
        else
            log_test "Token Introspection" "FAIL (token not active)"
        fi
    else
        log_test "Token Introspection" "FAIL"
    fi
else
    echo -e "${YELLOW}Skipping - No TEP token available${NC}"
    log_test "Token Introspection" "SKIP"
fi

# 2.3 Device Authorization Grant
echo -e "\n2.3 Testing Device Authorization Grant"
DEVICE_AUTH_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/v1/oauth2/device/authorization" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=ma_test_001" \
  -d "scope=user:read wallet:balance")
DEVICE_AUTH_CODE=$(echo "$DEVICE_AUTH_RESPONSE" | tail -n1)
DEVICE_AUTH_BODY=$(echo "$DEVICE_AUTH_RESPONSE" | head -n-1)
echo "Response Code: $DEVICE_AUTH_CODE"
echo "Response Body: $DEVICE_AUTH_BODY"
if [ "$DEVICE_AUTH_CODE" = "200" ]; then
    log_test "Device Authorization Grant" "PASS"
else
    log_test "Device Authorization Grant" "FAIL"
fi

# 2.4 OAuth Authorization Endpoint
echo -e "\n2.4 Testing OAuth Authorization Endpoint"
AUTHORIZE_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/api/v1/oauth/authorize?response_type=code&client_id=ma_test_001&redirect_uri=http://localhost:3000/callback&scope=user:read&state=test123")
AUTHORIZE_CODE=$(echo "$AUTHORIZE_RESPONSE" | tail -n1)
echo "Response Code: $AUTHORIZE_CODE"
# Note: This should redirect (302) or return consent page
if [ "$AUTHORIZE_CODE" = "302" ] || [ "$AUTHORIZE_CODE" = "200" ]; then
    log_test "OAuth Authorization Endpoint" "PASS"
else
    log_test "OAuth Authorization Endpoint" "FAIL"
fi

# ============================================================================
# SECTION 3: Capabilities Endpoint
# ============================================================================
print_section "3. Testing Capabilities Endpoint"

echo "3.1 Testing /api/v1/capabilities"
if [ -n "$TEP_TOKEN" ]; then
    CAPABILITIES_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/api/v1/capabilities" \
      -H "Authorization: Bearer ${TEP_TOKEN}")
    CAPABILITIES_CODE=$(echo "$CAPABILITIES_RESPONSE" | tail -n1)
    CAPABILITIES_BODY=$(echo "$CAPABILITIES_RESPONSE" | head -n-1)
    echo "Response Code: $CAPABILITIES_CODE"
    echo "Response Body: $CAPABILITIES_BODY" | jq '.' 2>/dev/null || echo "$CAPABILITIES_BODY"
    if [ "$CAPABILITIES_CODE" = "200" ]; then
        log_test "Capabilities Endpoint" "PASS"
    else
        log_test "Capabilities Endpoint" "FAIL"
    fi
else
    echo -e "${YELLOW}Skipping - No TEP token available${NC}"
    log_test "Capabilities Endpoint" "SKIP"
fi

# ============================================================================
# SECTION 4: Wallet Endpoints
# ============================================================================
print_section "4. Testing Wallet Endpoints"

# 4.1 Get Wallet Balance
echo "4.1 Testing GET /api/v1/wallet/balance"
if [ -n "$TEP_TOKEN" ]; then
    BALANCE_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/api/v1/wallet/balance" \
      -H "Authorization: Bearer ${TEP_TOKEN}")
    BALANCE_CODE=$(echo "$BALANCE_RESPONSE" | tail -n1)
    BALANCE_BODY=$(echo "$BALANCE_RESPONSE" | head -n-1)
    echo "Response Code: $BALANCE_CODE"
    echo "Response Body: $BALANCE_BODY" | jq '.' 2>/dev/null || echo "$BALANCE_BODY"
    if [ "$BALANCE_CODE" = "200" ]; then
        log_test "Get Wallet Balance" "PASS"
    else
        log_test "Get Wallet Balance" "FAIL"
    fi
else
    echo -e "${YELLOW}Skipping - No TEP token available${NC}"
    log_test "Get Wallet Balance" "SKIP"
fi

# 4.2 Get Transaction History
echo -e "\n4.2 Testing GET /api/v1/wallet/transactions"
if [ -n "$TEP_TOKEN" ]; then
    TRANSACTIONS_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/api/v1/wallet/transactions?limit=10&offset=0" \
      -H "Authorization: Bearer ${TEP_TOKEN}")
    TRANSACTIONS_CODE=$(echo "$TRANSACTIONS_RESPONSE" | tail -n1)
    TRANSACTIONS_BODY=$(echo "$TRANSACTIONS_RESPONSE" | head -n-1)
    echo "Response Code: $TRANSACTIONS_CODE"
    echo "Response Body: $TRANSACTIONS_BODY" | jq '.' 2>/dev/null || echo "$TRANSACTIONS_BODY"
    if [ "$TRANSACTIONS_CODE" = "200" ]; then
        log_test "Get Transaction History" "PASS"
    else
        log_test "Get Transaction History" "FAIL"
    fi
else
    echo -e "${YELLOW}Skipping - No TEP token available${NC}"
    log_test "Get Transaction History" "SKIP"
fi

# 4.3 Resolve User
echo -e "\n4.3 Testing GET /api/v1/wallet/resolve/:user_id"
if [ -n "$TEP_TOKEN" ]; then
    RESOLVE_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/api/v1/wallet/resolve/@mona:tween.im" \
      -H "Authorization: Bearer ${TEP_TOKEN}")
    RESOLVE_CODE=$(echo "$RESOLVE_RESPONSE" | tail -n1)
    RESOLVE_BODY=$(echo "$RESOLVE_RESPONSE" | head -n-1)
    echo "Response Code: $RESOLVE_CODE"
    echo "Response Body: $RESOLVE_BODY" | jq '.' 2>/dev/null || echo "$RESOLVE_BODY"
    if [ "$RESOLVE_CODE" = "200" ] || [ "$RESOLVE_CODE" = "404" ]; then
        log_test "Resolve User" "PASS"
    else
        log_test "Resolve User" "FAIL"
    fi
else
    echo -e "${YELLOW}Skipping - No TEP token available${NC}"
    log_test "Resolve User" "SKIP"
fi

# 4.4 Batch Resolve Users
echo -e "\n4.4 Testing POST /api/v1/wallet/resolve/batch"
if [ -n "$TEP_TOKEN" ]; then
    BATCH_RESOLVE_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/v1/wallet/resolve/batch" \
      -H "Authorization: Bearer ${TEP_TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{"user_ids": ["@mona:tween.im", "@test:tween.im"]}')
    BATCH_RESOLVE_CODE=$(echo "$BATCH_RESOLVE_RESPONSE" | tail -n1)
    BATCH_RESOLVE_BODY=$(echo "$BATCH_RESOLVE_RESPONSE" | head -n-1)
    echo "Response Code: $BATCH_RESOLVE_CODE"
    echo "Response Body: $BATCH_RESOLVE_BODY" | jq '.' 2>/dev/null || echo "$BATCH_RESOLVE_BODY"
    if [ "$BATCH_RESOLVE_CODE" = "200" ]; then
        log_test "Batch Resolve Users" "PASS"
    else
        log_test "Batch Resolve Users" "FAIL"
    fi
else
    echo -e "${YELLOW}Skipping - No TEP token available${NC}"
    log_test "Batch Resolve Users" "SKIP"
fi

# 4.5 P2P Transfer Initiate
echo -e "\n4.5 Testing POST /api/v1/wallet/p2p/initiate"
if [ -n "$TEP_TOKEN" ]; then
    P2P_INITIATE_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/v1/wallet/p2p/initiate" \
      -H "Authorization: Bearer ${TEP_TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{
        "recipient": "@test:tween.im",
        "amount": 10.00,
        "currency": "USD",
        "note": "Test transfer",
        "idempotency_key": "test-transfer-001"
      }')
    P2P_INITIATE_CODE=$(echo "$P2P_INITIATE_RESPONSE" | tail -n1)
    P2P_INITIATE_BODY=$(echo "$P2P_INITIATE_RESPONSE" | head -n-1)
    echo "Response Code: $P2P_INITIATE_CODE"
    echo "Response Body: $P2P_INITIATE_BODY" | jq '.' 2>/dev/null || echo "$P2P_INITIATE_BODY"
    if [ "$P2P_INITIATE_CODE" = "200" ] || [ "$P2P_INITIATE_CODE" = "201" ] || [ "$P2P_INITIATE_CODE" = "400" ]; then
        log_test "P2P Transfer Initiate" "PASS"
    else
        log_test "P2P Transfer Initiate" "FAIL"
    fi
else
    echo -e "${YELLOW}Skipping - No TEP token available${NC}"
    log_test "P2P Transfer Initiate" "SKIP"
fi

# ============================================================================
# SECTION 5: Payment Endpoints
# ============================================================================
print_section "5. Testing Payment Endpoints"

# 5.1 Create Payment Request
echo "5.1 Testing POST /api/v1/payments/request"
if [ -n "$TEP_TOKEN" ]; then
    PAYMENT_REQUEST_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/v1/payments/request" \
      -H "Authorization: Bearer ${TEP_TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{
        "amount": 15.00,
        "currency": "USD",
        "merchant": {
          "miniapp_id": "ma_test_001",
          "name": "Test Merchant"
        },
        "description": "Test payment",
        "idempotency_key": "test-payment-001"
      }')
    PAYMENT_REQUEST_CODE=$(echo "$PAYMENT_REQUEST_RESPONSE" | tail -n1)
    PAYMENT_REQUEST_BODY=$(echo "$PAYMENT_REQUEST_RESPONSE" | head -n-1)
    echo "Response Code: $PAYMENT_REQUEST_CODE"
    echo "Response Body: $PAYMENT_REQUEST_BODY" | jq '.' 2>/dev/null || echo "$PAYMENT_REQUEST_BODY"
    if [ "$PAYMENT_REQUEST_CODE" = "200" ] || [ "$PAYMENT_REQUEST_CODE" = "201" ]; then
        PAYMENT_ID=$(echo "$PAYMENT_REQUEST_BODY" | jq -r '.payment_id // empty')
        log_test "Payment Request" "PASS"
    else
        log_test "Payment Request" "FAIL"
    fi
else
    echo -e "${YELLOW}Skipping - No TEP token available${NC}"
    log_test "Payment Request" "SKIP"
fi

# 5.2 Payment Authorization (if payment_id available)
if [ -n "$PAYMENT_ID" ] && [ "$PAYMENT_ID" != "null" ]; then
    echo -e "\n5.2 Testing POST /api/v1/payments/:payment_id/authorize"
    PAYMENT_AUTH_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/v1/payments/${PAYMENT_ID}/authorize" \
      -H "Authorization: Bearer ${TEP_TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{
        "signature": "test_signature",
        "device_id": "test_device_001",
        "timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"
      }')
    PAYMENT_AUTH_CODE=$(echo "$PAYMENT_AUTH_RESPONSE" | tail -n1)
    PAYMENT_AUTH_BODY=$(echo "$PAYMENT_AUTH_RESPONSE" | head -n-1)
    echo "Response Code: $PAYMENT_AUTH_CODE"
    echo "Response Body: $PAYMENT_AUTH_BODY" | jq '.' 2>/dev/null || echo "$PAYMENT_AUTH_BODY"
    if [ "$PAYMENT_AUTH_CODE" = "200" ]; then
        log_test "Payment Authorization" "PASS"
    else
        log_test "Payment Authorization" "FAIL"
    fi
fi

# 5.3 Payment Refund
echo -e "\n5.3 Testing POST /api/v1/payments/:payment_id/refund"
if [ -n "$PAYMENT_ID" ] && [ "$PAYMENT_ID" != "null" ]; then
    REFUND_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/v1/payments/${PAYMENT_ID}/refund" \
      -H "Authorization: Bearer ${TEP_TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{
        "amount": 15.00,
        "reason": "customer_request",
        "notes": "Test refund"
      }')
    REFUND_CODE=$(echo "$REFUND_RESPONSE" | tail -n1)
    REFUND_BODY=$(echo "$REFUND_RESPONSE" | head -n-1)
    echo "Response Code: $REFUND_CODE"
    echo "Response Body: $REFUND_BODY" | jq '.' 2>/dev/null || echo "$REFUND_BODY"
    # Note: May return 400 if payment doesn't exist or can't be refunded
    if [ "$REFUND_CODE" = "200" ] || [ "$REFUND_CODE" = "400" ]; then
        log_test "Payment Refund" "PASS"
    else
        log_test "Payment Refund" "FAIL"
    fi
else
    echo -e "${YELLOW}Skipping - No payment_id available${NC}"
    log_test "Payment Refund" "SKIP"
fi

# ============================================================================
# SECTION 6: Gift Endpoints
# ============================================================================
print_section "6. Testing Gift Endpoints"

# 6.1 Create Gift
echo "6.1 Testing POST /api/v1/gifts/create"
if [ -n "$TEP_TOKEN" ]; then
    GIFT_CREATE_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/v1/gifts/create" \
      -H "Authorization: Bearer ${TEP_TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{
        "type": "individual",
        "recipient": "@test:tween.im",
        "amount": 20.00,
        "currency": "USD",
        "message": "Test gift",
        "room_id": "!test:tween.im",
        "idempotency_key": "test-gift-001"
      }')
    GIFT_CREATE_CODE=$(echo "$GIFT_CREATE_RESPONSE" | tail -n1)
    GIFT_CREATE_BODY=$(echo "$GIFT_CREATE_RESPONSE" | head -n-1)
    echo "Response Code: $GIFT_CREATE_CODE"
    echo "Response Body: $GIFT_CREATE_BODY" | jq '.' 2>/dev/null || echo "$GIFT_CREATE_BODY"
    if [ "$GIFT_CREATE_CODE" = "200" ] || [ "$GIFT_CREATE_CODE" = "201" ] || [ "$GIFT_CREATE_CODE" = "400" ]; then
        GIFT_ID=$(echo "$GIFT_CREATE_BODY" | jq -r '.gift_id // empty')
        log_test "Create Gift" "PASS"
    else
        log_test "Create Gift" "FAIL"
    fi
else
    echo -e "${YELLOW}Skipping - No TEP token available${NC}"
    log_test "Create Gift" "SKIP"
fi

# 6.2 Open Gift
if [ -n "$GIFT_ID" ] && [ "$GIFT_ID" != "null" ]; then
    echo -e "\n6.2 Testing POST /api/v1/gifts/:gift_id/open"
    GIFT_OPEN_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/v1/gifts/${GIFT_ID}/open" \
      -H "Authorization: Bearer ${TEP_TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{"device_id": "test_device_001"}')
    GIFT_OPEN_CODE=$(echo "$GIFT_OPEN_RESPONSE" | tail -n1)
    GIFT_OPEN_BODY=$(echo "$GIFT_OPEN_RESPONSE" | head -n-1)
    echo "Response Code: $GIFT_OPEN_CODE"
    echo "Response Body: $GIFT_OPEN_BODY" | jq '.' 2>/dev/null || echo "$GIFT_OPEN_BODY"
    if [ "$GIFT_OPEN_CODE" = "200" ]; then
        log_test "Open Gift" "PASS"
    else
        log_test "Open Gift" "FAIL"
    fi
fi

# ============================================================================
# SECTION 7: Storage Endpoints
# ============================================================================
print_section "7. Testing Storage Endpoints"

# 7.1 Get Storage Info
echo "7.1 Testing GET /api/v1/storage/info"
if [ -n "$TEP_TOKEN" ]; then
    STORAGE_INFO_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/api/v1/storage/info" \
      -H "Authorization: Bearer ${TEP_TOKEN}")
    STORAGE_INFO_CODE=$(echo "$STORAGE_INFO_RESPONSE" | tail -n1)
    STORAGE_INFO_BODY=$(echo "$STORAGE_INFO_RESPONSE" | head -n-1)
    echo "Response Code: $STORAGE_INFO_CODE"
    echo "Response Body: $STORAGE_INFO_BODY" | jq '.' 2>/dev/null || echo "$STORAGE_INFO_BODY"
    if [ "$STORAGE_INFO_CODE" = "200" ]; then
        log_test "Get Storage Info" "PASS"
    else
        log_test "Get Storage Info" "FAIL"
    fi
else
    echo -e "${YELLOW}Skipping - No TEP token available${NC}"
    log_test "Get Storage Info" "SKIP"
fi

# 7.2 Set Storage Value
echo -e "\n7.2 Testing PUT /api/v1/storage/:key"
if [ -n "$TEP_TOKEN" ]; then
    STORAGE_SET_RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT "${BASE_URL}/api/v1/storage/test_key" \
      -H "Authorization: Bearer ${TEP_TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{"value": "{\"test\": \"data\"}", "ttl": 3600}')
    STORAGE_SET_CODE=$(echo "$STORAGE_SET_RESPONSE" | tail -n1)
    STORAGE_SET_BODY=$(echo "$STORAGE_SET_RESPONSE" | head -n-1)
    echo "Response Code: $STORAGE_SET_CODE"
    echo "Response Body: $STORAGE_SET_BODY" | jq '.' 2>/dev/null || echo "$STORAGE_SET_BODY"
    if [ "$STORAGE_SET_CODE" = "200" ] || [ "$STORAGE_SET_CODE" = "201" ]; then
        log_test "Set Storage Value" "PASS"
    else
        log_test "Set Storage Value" "FAIL"
    fi
else
    echo -e "${YELLOW}Skipping - No TEP token available${NC}"
    log_test "Set Storage Value" "SKIP"
fi

# 7.3 Get Storage Value
echo -e "\n7.3 Testing GET /api/v1/storage/:key"
if [ -n "$TEP_TOKEN" ]; then
    STORAGE_GET_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/api/v1/storage/test_key" \
      -H "Authorization: Bearer ${TEP_TOKEN}")
    STORAGE_GET_CODE=$(echo "$STORAGE_GET_RESPONSE" | tail -n1)
    STORAGE_GET_BODY=$(echo "$STORAGE_GET_RESPONSE" | head -n-1)
    echo "Response Code: $STORAGE_GET_CODE"
    echo "Response Body: $STORAGE_GET_BODY" | jq '.' 2>/dev/null || echo "$STORAGE_GET_BODY"
    if [ "$STORAGE_GET_CODE" = "200" ] || [ "$STORAGE_GET_CODE" = "404" ]; then
        log_test "Get Storage Value" "PASS"
    else
        log_test "Get Storage Value" "FAIL"
    fi
else
    echo -e "${YELLOW}Skipping - No TEP token available${NC}"
    log_test "Get Storage Value" "SKIP"
fi

# 7.4 List Storage Keys
echo -e "\n7.4 Testing GET /api/v1/storage"
if [ -n "$TEP_TOKEN" ]; then
    STORAGE_LIST_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/api/v1/storage?prefix=test&limit=10" \
      -H "Authorization: Bearer ${TEP_TOKEN}")
    STORAGE_LIST_CODE=$(echo "$STORAGE_LIST_RESPONSE" | tail -n1)
    STORAGE_LIST_BODY=$(echo "$STORAGE_LIST_RESPONSE" | head -n-1)
    echo "Response Code: $STORAGE_LIST_CODE"
    echo "Response Body: $STORAGE_LIST_BODY" | jq '.' 2>/dev/null || echo "$STORAGE_LIST_BODY"
    if [ "$STORAGE_LIST_CODE" = "200" ]; then
        log_test "List Storage Keys" "PASS"
    else
        log_test "List Storage Keys" "FAIL"
    fi
else
    echo -e "${YELLOW}Skipping - No TEP token available${NC}"
    log_test "List Storage Keys" "SKIP"
fi

# 7.5 Batch Storage Operations
echo -e "\n7.5 Testing POST /api/v1/storage/batch"
if [ -n "$TEP_TOKEN" ]; then
    STORAGE_BATCH_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/v1/storage/batch" \
      -H "Authorization: Bearer ${TEP_TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{"operation": "get", "keys": ["test_key", "key2"]}')
    STORAGE_BATCH_CODE=$(echo "$STORAGE_BATCH_RESPONSE" | tail -n1)
    STORAGE_BATCH_BODY=$(echo "$STORAGE_BATCH_RESPONSE" | head -n-1)
    echo "Response Code: $STORAGE_BATCH_CODE"
    echo "Response Body: $STORAGE_BATCH_BODY" | jq '.' 2>/dev/null || echo "$STORAGE_BATCH_BODY"
    if [ "$STORAGE_BATCH_CODE" = "200" ]; then
        log_test "Batch Storage Operations" "PASS"
    else
        log_test "Batch Storage Operations" "FAIL"
    fi
else
    echo -e "${YELLOW}Skipping - No TEP token available${NC}"
    log_test "Batch Storage Operations" "SKIP"
fi

# 7.6 Delete Storage Value
echo -e "\n7.6 Testing DELETE /api/v1/storage/:key"
if [ -n "$TEP_TOKEN" ]; then
    STORAGE_DELETE_RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE "${BASE_URL}/api/v1/storage/test_key" \
      -H "Authorization: Bearer ${TEP_TOKEN}")
    STORAGE_DELETE_CODE=$(echo "$STORAGE_DELETE_RESPONSE" | tail -n1)
    STORAGE_DELETE_BODY=$(echo "$STORAGE_DELETE_RESPONSE" | head -n-1)
    echo "Response Code: $STORAGE_DELETE_CODE"
    echo "Response Body: $STORAGE_DELETE_BODY" | jq '.' 2>/dev/null || echo "$STORAGE_DELETE_BODY"
    if [ "$STORAGE_DELETE_CODE" = "200" ] || [ "$STORAGE_DELETE_CODE" = "204" ]; then
        log_test "Delete Storage Value" "PASS"
    else
        log_test "Delete Storage Value" "FAIL"
    fi
else
    echo -e "${YELLOW}Skipping - No TEP token available${NC}"
    log_test "Delete Storage Value" "SKIP"
fi

# ============================================================================
# SECTION 8: Store/App Endpoints
# ============================================================================
print_section "8. Testing Store/App Endpoints"

# 8.1 Get Categories
echo "8.1 Testing GET /api/v1/store/categories"
if [ -n "$TEP_TOKEN" ]; then
    CATEGORIES_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/api/v1/store/categories" \
      -H "Authorization: Bearer ${TEP_TOKEN}")
    CATEGORIES_CODE=$(echo "$CATEGORIES_RESPONSE" | tail -n1)
    CATEGORIES_BODY=$(echo "$CATEGORIES_RESPONSE" | head -n-1)
    echo "Response Code: $CATEGORIES_CODE"
    echo "Response Body: $CATEGORIES_BODY" | jq '.' 2>/dev/null || echo "$CATEGORIES_BODY"
    if [ "$CATEGORIES_CODE" = "200" ]; then
        log_test "Get Categories" "PASS"
    else
        log_test "Get Categories" "FAIL"
    fi
else
    echo -e "${YELLOW}Skipping - No TEP token available${NC}"
    log_test "Get Categories" "SKIP"
fi

# 8.2 Get Apps
echo -e "\n8.2 Testing GET /api/v1/store/apps"
if [ -n "$TEP_TOKEN" ]; then
    APPS_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/api/v1/store/apps?limit=10" \
      -H "Authorization: Bearer ${TEP_TOKEN}")
    APPS_CODE=$(echo "$APPS_RESPONSE" | tail -n1)
    APPS_BODY=$(echo "$APPS_RESPONSE" | head -n-1)
    echo "Response Code: $APPS_CODE"
    echo "Response Body: $APPS_BODY" | jq '.' 2>/dev/null || echo "$APPS_BODY"
    if [ "$APPS_CODE" = "200" ]; then
        log_test "Get Apps" "PASS"
    else
        log_test "Get Apps" "FAIL"
    fi
else
    echo -e "${YELLOW}Skipping - No TEP token available${NC}"
    log_test "Get Apps" "SKIP"
fi

# ============================================================================
# SECTION 9: OAuth Authorization Code/Callback
# ============================================================================
print_section "9. Testing OAuth Authorization Code Flow"

# 9.1 OAuth Callback
echo "9.1 Testing OAuth Callback Endpoint"
OAUTH_CALLBACK_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/api/v1/oauth2/callback?code=test_code&state=test123")
OAUTH_CALLBACK_CODE=$(echo "$OAUTH_CALLBACK_RESPONSE" | tail -n1)
echo "Response Code: $OAUTH_CALLBACK_CODE"
if [ "$OAUTH_CALLBACK_CODE" = "302" ] || [ "$OAUTH_CALLBACK_CODE" = "200" ]; then
    log_test "OAuth Callback Endpoint" "PASS"
else
    log_test "OAuth Callback Endpoint" "FAIL"
fi

# 9.2 OAuth Consent
echo -e "\n9.2 Testing OAuth Consent Endpoint"
OAUTH_CONSENT_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/v1/oauth2/consent" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "session=test_session&approve=true&scopes=user:read")
OAUTH_CONSENT_CODE=$(echo "$OAUTH_CONSENT_RESPONSE" | tail -n1)
echo "Response Code: $OAUTH_CONSENT_CODE"
if [ "$OAUTH_CONSENT_CODE" = "200" ] || [ "$OAUTH_CONSENT_CODE" = "302" ]; then
    log_test "OAuth Consent Endpoint" "PASS"
else
    log_test "OAuth Consent Endpoint" "FAIL"
fi

# ============================================================================
# Print Summary
# ============================================================================
print_section "Test Summary"
echo -e "Total Tests: $TOTAL"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo -e "${YELLOW}Skipped: $((TOTAL - PASSED - FAILED))${NC}"

exit $FAILED
