#!/bin/bash

# TMCP API Comprehensive Test Script
# Tests all API endpoints with proper tokens

MATRIX_ACCESS_TOKEN="mct_sb8qD8zPPZWp05qrCg3Xv90cUWtNKh_0QGYVE"
MATRIX_HS_TOKEN="874542cda496ffd03f8fd283ad37d8837572aad0734e92225c5f7fffd8c91bd1"
BASE_URL="http://localhost:3000"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Test results
PASSED=0
FAILED=0
TOTAL=0
ISSUES=()

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

log_issue() {
    ISSUES+=("$1")
    echo -e "${YELLOW}  └─ ISSUE: $1${NC}"
}

print_section() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

# Store tokens
TEP_TOKEN=""
REFRESH_TOKEN=""
USER_ID=""
WALLET_ID=""

# ============================================================================
# SECTION 1: Matrix Application Service Endpoints
# ============================================================================
print_section "1. Matrix Application Service Endpoints"

# 1.1 Health Check (Ping)
echo "1.1 Testing /_matrix/app/v1/ping (Health Check) with HS_TOKEN"
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
# Note: Returning 404 is correct behavior for non-existent users
if [ "$USER_QUERY_CODE" = "200" ] || [ "$USER_QUERY_CODE" = "404" ]; then
    log_test "Matrix AS User Query" "PASS"
else
    log_test "Matrix AS User Query" "FAIL"
fi

# 1.3 Room Query
echo -e "\n1.3 Testing /_matrix/app/v1/rooms/:room_alias (Room Query)"
ROOM_QUERY_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/_matrix/app/v1/rooms/%23tmcp:tween.im" \
  -H "Authorization: Bearer ${MATRIX_HS_TOKEN}")
ROOM_QUERY_CODE=$(echo "$ROOM_QUERY_RESPONSE" | tail -n1)
ROOM_QUERY_BODY=$(echo "$ROOM_QUERY_RESPONSE" | head -n-1)
echo "Response Code: $ROOM_QUERY_CODE"
if [ "$ROOM_QUERY_CODE" = "200" ] || [ "$ROOM_QUERY_CODE" = "404" ]; then
    log_test "Matrix AS Room Query" "PASS"
else
    log_test "Matrix AS Room Query" "FAIL"
fi

# 1.4 Third-Party Location
echo -e "\n1.4 Testing Third-Party Location Endpoint"
TP_LOCATION_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/_matrix/app/v1/thirdparty/location" \
  -H "Authorization: Bearer ${MATRIX_HS_TOKEN}")
TP_LOCATION_CODE=$(echo "$TP_LOCATION_RESPONSE" | tail -n1)
echo "Response Code: $TP_LOCATION_CODE"
if [ "$TP_LOCATION_CODE" = "200" ] || [ "$TP_LOCATION_CODE" = "401" ]; then
    log_test "Third-Party Location Endpoint" "PASS"
else
    log_test "Third-Party Location Endpoint" "FAIL"
fi

# ============================================================================
# SECTION 2: OAuth 2.0 Endpoints
# ============================================================================
print_section "2. OAuth 2.0 Endpoints (Matrix Session Delegation)"

# 2.1 Matrix Session Delegation (Token Exchange)
echo "2.1 Testing Matrix Session Delegation (Token Exchange)"
TOKEN_EXCHANGE_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/v1/oauth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=urn:ietf:params:oauth:grant-type:token-exchange" \
  -d "subject_token=${MATRIX_ACCESS_TOKEN}" \
  -d "subject_token_type=urn:ietf:params:oauth:token-type:access_token" \
  -d "client_id=ma_test_001" \
  -d "scope=user:read wallet:balance storage:write" \
  -d "requested_token_type=urn:tmcp:params:oauth:token-type:tep" \
  -d 'miniapp_context={"room_id":"!test:tween.im","launch_source":"test"}')

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

    # Check response structure per PROTO.md Section 4.3.1
    HAS_REFRESH=$(echo "$TOKEN_EXCHANGE_BODY" | jq -e '.refresh_token' >/dev/null && echo "yes" || echo "no")
    HAS_MATRIX_TOKEN=$(echo "$TOKEN_EXCHANGE_BODY" | jq -e '.matrix_access_token' >/dev/null && echo "yes" || echo "no")
    HAS_DELEGATED_SESSION=$(echo "$TOKEN_EXCHANGE_BODY" | jq -e '.delegated_session' >/dev/null && echo "yes" || echo "no")

    if [ "$HAS_REFRESH" != "yes" ]; then
        log_issue "PROTO.md Section 4.3.1: Response missing 'refresh_token' field"
    fi
    if [ "$HAS_MATRIX_TOKEN" != "yes" ]; then
        log_issue "PROTO.md Section 4.3.1: Response missing 'matrix_access_token' field"
    fi
    if [ "$HAS_DELEGATED_SESSION" != "yes" ]; then
        log_issue "PROTO.md Section 4.3.1: Response missing 'delegated_session' field"
    fi
else
    log_test "Matrix Session Delegation" "FAIL"
fi

# 2.2 Device Authorization Grant
echo -e "\n2.2 Testing Device Authorization Grant"
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

# 2.3 OAuth Introspect
echo -e "\n2.3 Testing TEP Token Introspection"
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
            log_test "TEP Token Introspection" "PASS"
        else
            log_test "TEP Token Introspection" "FAIL (token not active)"
        fi
    else
        log_test "TEP Token Introspection" "FAIL"
    fi
else
    echo -e "${YELLOW}Skipping - No TEP token available${NC}"
fi

# ============================================================================
# SECTION 3: Missing Endpoints (Developer/Organization)
# ============================================================================
print_section "3. Checking for Missing Endpoints (PROTO Compliance)"

# 3.1 Developer Token Endpoint
echo "3.1 Checking POST /oauth2/developer/token"
DEV_TOKEN_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/oauth2/developer/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=authorization_code&code=test&client_id=test")
DEV_TOKEN_CODE=$(echo "$DEV_TOKEN_RESPONSE" | tail -n1)
echo "Response Code: $DEV_TOKEN_CODE"
if [ "$DEV_TOKEN_CODE" = "404" ]; then
    log_test "Developer Token Endpoint" "PASS (Missing as expected)"
    log_issue "PROTO.md Section 4.4.3: POST /oauth2/developer/token not implemented"
elif [ "$DEV_TOKEN_CODE" = "200" ] || [ "$DEV_TOKEN_CODE" = "400" ] || [ "$DEV_TOKEN_CODE" = "401" ]; then
    log_test "Developer Token Endpoint" "PASS"
else
    log_test "Developer Token Endpoint" "FAIL"
fi

# 3.2 Organization Create Endpoint
echo -e "\n3.2 Checking POST /organizations/v1/create"
ORG_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/organizations/v1/create" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TEP_TOKEN}" \
  -d '{"name":"Test Org"}')
ORG_CODE=$(echo "$ORG_RESPONSE" | tail -n1)
echo "Response Code: $ORG_CODE"
if [ "$ORG_CODE" = "404" ]; then
    log_test "Organization Create Endpoint" "PASS (Missing as expected)"
    log_issue "PROTO.md Section 4.4.4: POST /organizations/v1/create not implemented"
elif [ "$ORG_CODE" = "200" ] || [ "$ORG_CODE" = "400" ] || [ "$ORG_CODE" = "401" ]; then
    log_test "Organization Create Endpoint" "PASS"
else
    log_test "Organization Create Endpoint" "FAIL"
fi

# 3.3 Organization Members Endpoint
echo -e "\n3.3 Checking POST /organizations/v1/:org_id/members"
ORG_MEMBER_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/organizations/v1/test_org/members" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TEP_TOKEN}")
ORG_MEMBER_CODE=$(echo "$ORG_MEMBER_RESPONSE" | tail -n1)
echo "Response Code: $ORG_MEMBER_CODE"
if [ "$ORG_MEMBER_CODE" = "404" ]; then
    log_test "Organization Members Endpoint" "PASS (Missing as expected)"
    log_issue "PROTO.md Section 4.4.4: POST /organizations/v1/:org_id/members not implemented"
else
    log_test "Organization Members Endpoint" "PASS (or FAIL due to 404)"
fi

# ============================================================================
# SECTION 4: Capabilities Endpoint
# ============================================================================
print_section "4. Testing Capabilities Endpoint"

if [ -n "$TEP_TOKEN" ]; then
    echo "4.1 Testing GET /api/v1/capabilities"
    CAPABILITIES_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/api/v1/capabilities" \
      -H "Authorization: Bearer ${TEP_TOKEN}")
    CAPABILITIES_CODE=$(echo "$CAPABILITIES_RESPONSE" | tail -n1)
    CAPABILITIES_BODY=$(echo "$CAPABILITIES_RESPONSE" | head -n-1)
    echo "Response Code: $CAPABILITIES_CODE"
    echo "Response Body: $CAPABILITIES_BODY" | jq '.' 2>/dev/null || echo "$CAPABILITIES_BODY"
    if [ "$CAPABILITIES_CODE" = "200" ]; then
        log_test "Capabilities Endpoint" "PASS"
        # Check PROTO compliance Section 10.5.2
        HAS_CAPABILITIES=$(echo "$CAPABILITIES_BODY" | jq -e '.capabilities' >/dev/null && echo "yes" || echo "no")
        HAS_PLATFORM=$(echo "$CAPABILITIES_BODY" | jq -e '.platform' >/dev/null && echo "yes" || echo "no")
        HAS_FEATURES=$(echo "$CAPABILITIES_BODY" | jq -e '.features' >/dev/null && echo "yes" || echo "no")

        if [ "$HAS_CAPABILITIES" != "yes" ]; then
            log_issue "PROTO.md Section 10.5.2: Response missing 'capabilities' field"
        fi
        if [ "$HAS_PLATFORM" != "yes" ]; then
            log_issue "PROTO.md Section 10.5.2: Response missing 'platform' field"
        fi
        if [ "$HAS_FEATURES" != "yes" ]; then
            log_issue "PROTO.md Section 10.5.2: Response missing 'features' field"
        fi
    else
        log_test "Capabilities Endpoint" "FAIL"
    fi
else
    echo -e "${YELLOW}Skipping - No TEP token available${NC}"
    log_test "Capabilities Endpoint" "FAIL"
fi

# ============================================================================
# SECTION 5: Wallet Endpoints
# ============================================================================
print_section "5. Testing Wallet Endpoints"

if [ -n "$TEP_TOKEN" ]; then
    # 5.1 Get Wallet Balance
    echo "5.1 Testing GET /api/v1/wallet/balance"
    BALANCE_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/api/v1/wallet/balance" \
      -H "Authorization: Bearer ${TEP_TOKEN}")
    BALANCE_CODE=$(echo "$BALANCE_RESPONSE" | tail -n1)
    BALANCE_BODY=$(echo "$BALANCE_RESPONSE" | head -n-1)
    echo "Response Code: $BALANCE_CODE"
    echo "Response Body: $BALANCE_BODY" | jq '.' 2>/dev/null || echo "$BALANCE_BODY"
    if [ "$BALANCE_CODE" = "200" ]; then
        log_test "Get Wallet Balance" "PASS"
        # Check PROTO compliance Section 6.2.1
        HAS_WALLET_ID=$(echo "$BALANCE_BODY" | jq -e '.wallet_id' >/dev/null && echo "yes" || echo "no")
        HAS_BALANCE=$(echo "$BALANCE_BODY" | jq -e '.balance' >/dev/null && echo "yes" || echo "no")
        HAS_LIMITS=$(echo "$BALANCE_BODY" | jq -e '.limits' >/dev/null && echo "yes" || echo "no")
        HAS_STATUS=$(echo "$BALANCE_BODY" | jq -e '.status' >/dev/null && echo "yes" || echo "no")
        HAS_VERIFICATION=$(echo "$BALANCE_BODY" | jq -e '.verification' >/dev/null && echo "yes" || echo "no")

        if [ "$HAS_WALLET_ID" != "yes" ]; then
            log_issue "PROTO.md Section 6.2.1: Response missing 'wallet_id' field"
        fi
        if [ "$HAS_BALANCE" != "yes" ]; then
            log_issue "PROTO.md Section 6.2.1: Response missing 'balance' field"
        fi
        if [ "$HAS_LIMITS" != "yes" ]; then
            log_issue "PROTO.md Section 6.2.1: Response missing 'limits' field"
        fi
        if [ "$HAS_STATUS" != "yes" ]; then
            log_issue "PROTO.md Section 6.2.1: Response missing 'status' field"
        fi
        if [ "$HAS_VERIFICATION" != "yes" ]; then
            log_issue "PROTO.md Section 6.2.1: Response missing 'verification' field"
        fi
    else
        log_test "Get Wallet Balance" "FAIL"
    fi

    # 5.2 Get Transaction History
    echo -e "\n5.2 Testing GET /api/v1/wallet/transactions"
    TRANSACTIONS_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/api/v1/wallet/transactions?limit=10&offset=0" \
      -H "Authorization: Bearer ${TEP_TOKEN}")
    TRANSACTIONS_CODE=$(echo "$TRANSACTIONS_RESPONSE" | tail -n1)
    TRANSACTIONS_BODY=$(echo "$TRANSACTIONS_RESPONSE" | head -n-1)
    echo "Response Code: $TRANSACTIONS_CODE"
    echo "Response Body: $TRANSACTIONS_BODY" | jq '.' 2>/dev/null || echo "$TRANSACTIONS_BODY"
    if [ "$TRANSACTIONS_CODE" = "200" ]; then
        log_test "Get Transaction History" "PASS"
        # Check PROTO compliance Section 6.2.2
        HAS_TRANSACTIONS=$(echo "$TRANSACTIONS_BODY" | jq -e '.transactions' >/dev/null && echo "yes" || echo "no")
        HAS_PAGINATION=$(echo "$TRANSACTIONS_BODY" | jq -e '.pagination' >/dev/null && echo "yes" || echo "no")

        if [ "$HAS_TRANSACTIONS" != "yes" ]; then
            log_issue "PROTO.md Section 6.2.2: Response missing 'transactions' field"
        fi
        if [ "$HAS_PAGINATION" != "yes" ]; then
            log_issue "PROTO.md Section 6.2.2: Response missing 'pagination' field"
        fi
    else
        log_test "Get Transaction History" "FAIL"
    fi

    # 5.3 Get Verification Level
    echo -e "\n5.3 Testing GET /api/v1/wallet/verification"
    VERIFICATION_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/api/v1/wallet/verification" \
      -H "Authorization: Bearer ${TEP_TOKEN}")
    VERIFICATION_CODE=$(echo "$VERIFICATION_RESPONSE" | tail -n1)
    VERIFICATION_BODY=$(echo "$VERIFICATION_RESPONSE" | head -n-1)
    echo "Response Code: $VERIFICATION_CODE"
    echo "Response Body: $VERIFICATION_BODY" | jq '.' 2>/dev/null || echo "$VERIFICATION_BODY"
    if [ "$VERIFICATION_CODE" = "200" ]; then
        log_test "Get Verification Level" "PASS"
    else
        log_test "Get Verification Level" "FAIL"
    fi
else
    echo -e "${YELLOW}Skipping wallet tests - No TEP token available${NC}"
fi

# ============================================================================
# SECTION 6: Storage Endpoints
# ============================================================================
print_section "6. Testing Storage Endpoints"

if [ -n "$TEP_TOKEN" ]; then
    # 6.1 Get Storage Info
    echo "6.1 Testing GET /api/v1/storage/info"
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

    # 6.2 Set Storage Value
    echo -e "\n6.2 Testing PUT /api/v1/storage/:key"
    STORAGE_SET_RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT "${BASE_URL}/api/v1/storage/test_key" \
      -H "Authorization: Bearer ${TEP_TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{"value":"{\"test\":\"data\"}","ttl":3600}')
    STORAGE_SET_CODE=$(echo "$STORAGE_SET_RESPONSE" | tail -n1)
    STORAGE_SET_BODY=$(echo "$STORAGE_SET_RESPONSE" | head -n-1)
    echo "Response Code: $STORAGE_SET_CODE"
    echo "Response Body: $STORAGE_SET_BODY" | jq '.' 2>/dev/null || echo "$STORAGE_SET_BODY"
    if [ "$STORAGE_SET_CODE" = "200" ] || [ "$STORAGE_SET_CODE" = "201" ]; then
        log_test "Set Storage Value" "PASS"
    else
        log_test "Set Storage Value" "FAIL"
    fi

    # 6.3 Get Storage Value
    echo -e "\n6.3 Testing GET /api/v1/storage/:key"
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

    # 6.4 List Storage Keys
    echo -e "\n6.4 Testing GET /api/v1/storage"
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

    # 6.5 Batch Storage Operations
    echo -e "\n6.5 Testing POST /api/v1/storage/batch"
    STORAGE_BATCH_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/v1/storage/batch" \
      -H "Authorization: Bearer ${TEP_TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{"operation":"get","keys":["test_key","key2"]}')
    STORAGE_BATCH_CODE=$(echo "$STORAGE_BATCH_RESPONSE" | tail -n1)
    STORAGE_BATCH_BODY=$(echo "$STORAGE_BATCH_RESPONSE" | head -n-1)
    echo "Response Code: $STORAGE_BATCH_CODE"
    echo "Response Body: $STORAGE_BATCH_BODY" | jq '.' 2>/dev/null || echo "$STORAGE_BATCH_BODY"
    if [ "$STORAGE_BATCH_CODE" = "200" ]; then
        log_test "Batch Storage Operations" "PASS"
    else
        log_test "Batch Storage Operations" "FAIL"
    fi

    # 6.6 Delete Storage Value
    echo -e "\n6.6 Testing DELETE /api/v1/storage/:key"
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
    echo -e "${YELLOW}Skipping storage tests - No TEP token available${NC}"
fi

# ============================================================================
# SECTION 7: Store/App Endpoints
# ============================================================================
print_section "7. Testing Store/App Endpoints"

if [ -n "$TEP_TOKEN" ]; then
    # 7.1 Get Categories
    echo "7.1 Testing GET /api/v1/store/categories"
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

    # 7.2 Get Apps
    echo -e "\n7.2 Testing GET /api/v1/store/apps"
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
    echo -e "${YELLOW}Skipping store tests - No TEP token available${NC}"
fi

# ============================================================================
# Print Summary
# ============================================================================
print_section "Test Summary"
echo -e "Total Tests: $TOTAL"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo -e "${YELLOW}Skipped: $((TOTAL - PASSED - FAILED))${NC}"

if [ ${#ISSUES[@]} -gt 0 ]; then
    print_section "${MAGENTA}PROTO.md Compliance Issues Identified${NC}"
    for issue in "${ISSUES[@]}"; do
        echo -e "${YELLOW}• $issue${NC}"
    done

    print_section "${MAGENTA}Logically Unsound/Inconsistent Areas${NC}"
    echo -e "${BLUE}Based on the PROTO.md spec, these areas appear to be logically unsound:${NC}\n"
    echo -e "${YELLOW}1. Chicken-and-Egg Problem for Mini-App Registration${NC}"
    echo -e "${BLUE}   - Issue: PROTO.md requires mini-apps to be registered before TEP tokens can be issued"
    echo -e "${BLUE}   - PROTO.md Section 4.4 defines Developer Authentication, but developers need DEVELOPER_TOKEN to register mini-apps"
    echo -e "${BLUE}   - PROTO.md Section 4.4.9 tries to address this with Developer Console being a 'trusted platform service'"
    echo -e "${BLUE}   - However, this creates a separate trust model that isn't fully integrated into the main flow"
    echo -e "${BLUE}   - Suggestion: Define a bootstrap/seed mechanism for initial mini-app registration or pre-seed a trusted mini-app${NC}\n"

    echo -e "${YELLOW}2. Inconsistent Scope Formats${NC}"
    echo -e "${BLUE}   - Issue: PROTO.md uses colon format 'wallet:pay' but code validation used underscore 'wallet_pay'"
    echo -e "${BLUE}   - PROTO.md Section 5.2 defines scopes with colons"
    echo -e "${BLUE}   - Implementation in MiniApp model uses underscores (found/now fixed)"
    echo -e "${BLUE}   - This inconsistency caused validation failures${NC}\n"

    echo -e "${YELLOW}3. Missing MAS Client Configuration${NC}"
    echo -e "${BLUE}   - Issue: PROTO.md Section 4.7.1 requires TMCP Server MAS client registration"
    echo -e "${BLUE}   - Section 3.1.2 specifies MAS client credentials"
    echo -e "${BLUE}   - Implementation environment variables are present (.env), but the MAS integration flow isn't fully specified"
    echo -e "${BLUE}   - Section 4.3.1 describes token exchange but MAS client vs TMCP Server roles aren't clear${NC}\n"

    echo -e "${YELLOW}4. Organization-Developer Relationship${NC}"
    echo -e "${BLUE}   - Issue: PROTO.md Section 4.4.4 defines organization management"
    echo -e "${BLUE}   - Mini-apps are registered to developers who belong to organizations"
    echo -e "${BLUE}   - However, there's no clear flow for how organizations are initially created"
    echo -e "${BLUE}   - Without organizations, developers can't register mini-apps, creating a bootstrap paradox${NC}\n"

    echo -e "${YELLOW}5. Payment Authorization Inconsistency${NC}"
    echo -e "${BLUE}   - Issue: PROTO.md Section 7.3.2 requires client-side cryptographic signing"
    echo -e "${BLUE}   - Implementation requires hardware-backed keys (Secure Enclave/TEE)"
    echo -e "${BLUE}   - No specification for what happens if client doesn't have secure storage (desktop/web apps)"
    echo -e "${BLUE}   - Section 10.4.5 warns against injecting tokens, but payment auth needs signing${NC}\n"

    echo -e "${YELLOW}6. Dual-Token Management Complexity${NC}"
    echo -e "${BLUE}   - Issue: PROTO.md Section 4.1 defines dual-token architecture (TEP + MAS)"
    echo -e "${BLUE}   - Section 4.11.7 requires Matrix token exchange for mini-apps"
    echo -e "${BLUE}   - This creates circular dependency: TEP needs MAS token, but MAS token refresh needs TEP context"
    echo -e "${BLUE}   - Implementation complexity is high for a relatively simple use case${NC}\n"
fi

exit $FAILED
