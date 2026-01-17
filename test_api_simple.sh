#!/bin/bash

# TMCP API Test Script - Simplified for testing
# Tests API endpoints and identifies PROTO.md compliance issues

MATRIX_ACCESS_TOKEN="mct_sb8qD8zPPZWp05qrCg3Xv90cUWtNKh_0QGYVE"
BASE_URL="http://localhost:3000"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
        ISSUES+=("$test_name")
    fi
}

print_section() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

# Store tokens
TEP_TOKEN=""

# ============================================================================
# SECTION 1: Matrix Application Service Endpoints
# ============================================================================
print_section "1. Testing Matrix Application Service Endpoints"

# 1.1 Health Check (Ping)
echo "1.1 Testing /_matrix/app/v1/ping (Health Check)"
PING_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/_matrix/app/v1/ping")
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
USER_QUERY_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/_matrix/app/v1/users/@mona:tween.im")
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
ROOM_QUERY_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/_matrix/app/v1/rooms/%23tmcp:tween.im")
ROOM_QUERY_CODE=$(echo "$ROOM_QUERY_RESPONSE" | tail -n1)
ROOM_QUERY_BODY=$(echo "$ROOM_QUERY_RESPONSE" | head -n-1)
echo "Response Code: $ROOM_QUERY_CODE"
echo "Response Body: $ROOM_QUERY_BODY"
# Note: URL encoding # as %23
if [ "$ROOM_QUERY_CODE" = "200" ] || [ "$ROOM_QUERY_CODE" = "404" ]; then
    log_test "Matrix AS Room Query" "PASS"
else
    log_test "Matrix AS Room Query" "FAIL"
fi

# 1.4 Third-Party Protocol Endpoints
echo -e "\n1.4 Testing Third-Party Location Endpoint"
TP_LOCATION_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/_matrix/app/v1/thirdparty/location")
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
print_section "2. Testing OAuth 2.0 Endpoints"

# 2.1 Matrix Session Delegation (Token Exchange)
echo "2.1 Testing Matrix Session Delegation (Token Exchange)"
echo "Note: Requires pre-registered mini-app. Testing with ma_test_001..."
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
else
    log_test "Matrix Session Delegation" "FAIL"
    echo -e "${YELLOW}Note: Mini-app not pre-registered in Doorkeeper. This is a setup issue.${NC}"
    echo -e "${YELLOW}     PROTO ISSUE: Protocol doesn't specify how to bootstrap first mini-app registration${NC}"
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
# Device auth works even without registration (code only)
if [ "$DEVICE_AUTH_CODE" = "200" ]; then
    log_test "Device Authorization Grant" "PASS"
else
    log_test "Device Authorization Grant" "FAIL"
fi

# ============================================================================
# SECTION 3: Check for Developer/Organization endpoints
# ============================================================================
print_section "3. Checking for Developer/Organization Endpoints"

# Check if developer registration exists
echo "3.1 Checking for Developer Registration Endpoint"
DEV_REG_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/oauth2/developer/token")
DEV_REG_CODE=$(echo "$DEV_REG_RESPONSE" | tail -n1)
echo "Response Code: $DEV_REG_CODE"
if [ "$DEV_REG_CODE" = "404" ]; then
    echo -e "${YELLOW}Developer token endpoint not implemented${NC}"
    echo -e "${YELLOW}     PROTO ISSUE: PROTO.md specifies developer authentication (Section 4.4), but no endpoints exist${NC}"
    ISSUES+=("Developer Authentication endpoints missing")
elif [ "$DEV_REG_CODE" = "405" ] || [ "$DEV_REG_CODE" = "200" ]; then
    log_test "Developer Registration Endpoint" "PASS"
else
    log_test "Developer Registration Endpoint" "FAIL"
fi

# Check organization endpoints
echo -e "\n3.2 Checking for Organization Management Endpoint"
ORG_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/organizations/v1/create")
ORG_CODE=$(echo "$ORG_RESPONSE" | tail -n1)
echo "Response Code: $ORG_CODE"
if [ "$ORG_CODE" = "404" ]; then
    echo -e "${YELLOW}Organization endpoint not implemented${NC}"
    echo -e "${YELLOW}     PROTO ISSUE: PROTO.md specifies organization management (Section 4.4.4), but no endpoints exist${NC}"
    ISSUES+=("Organization Management endpoints missing")
elif [ "$ORG_CODE" = "401" ] || [ "$ORG_CODE" = "400" ]; then
    # Endpoint exists but requires auth
    log_test "Organization Management Endpoint" "PASS"
else
    log_test "Organization Management Endpoint" "FAIL"
fi

# ============================================================================
# SECTION 4: TEP Token Introspection
# ============================================================================
print_section "4. Testing TEP Token Introspection"

if [ -n "$TEP_TOKEN" ]; then
    echo "4.1 Testing POST /api/v1/oauth2/introspect with TEP token"
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
    log_test "TEP Token Introspection" "SKIP"
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
    print_section "PROTO.md Compliance Issues Identified"
    for issue in "${ISSUES[@]}"; do
        echo -e "${YELLOW}• $issue${NC}"
    done
fi

exit 0
