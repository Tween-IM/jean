# TMCP Application Service Deployment Verification - Detailed Steps

## Overview

This document provides step-by-step deployment verification instructions to confirm your TMCP application service has successfully registered with your Synapse server.

## Prerequisites

Before starting verification:
- Ensure your TMCP server is deployed and running
- Have your Synapse server URL and admin token ready
- Know your TMCP application service ID (from config/initializers/tmcp.rb)
- Have your TMCP server URL accessible

## Step 1: Verify Synapse Application Service Registration

### 1.1 Check Application Service List
```bash
# Get list of registered application services
curl -H "Authorization: Bearer YOUR_HOMESERVER_TOKEN" \
     "https://your.matrix.server/_synapse/admin/v1/appservice"
```

Look for your TMCP application service in the response. It should include:
- `id`: Your application service ID (e.g., "tmcp_app_service")
- `url`: Your TMCP server URL (e.g., "https://your.tmcp.server/api/v1/matrix/events")
- `sender_localpart`: Application service user (e.g., "@tmcp:")
- `namespaces`: Room and user namespaces configured

### 1.2 Check Specific Application Service Details
```bash
# Get details for your specific application service
curl -H "Authorization: Bearer YOUR_HOMESERVER_TOKEN" \
     "https://your.matrix.server/_synapse/admin/v1/appservice/register?service_name=YOUR_APP_SERVICE_ID"
```

### 1.3 Verify Namespace Registration
```bash
# Check room namespaces
curl -H "Authorization: Bearer YOUR_HOMESERVER_TOKEN" \
     "https://your.matrix.server/_synapse/admin/v1/appservice/namespace?service_name=YOUR_APP_SERVICE_ID"

# Check user namespaces
curl -H "Authorization: Bearer YOUR_HOMESERVER_TOKEN" \
     "https://your.matrix.server/_synapse/admin/v1/appservice/namespace?service_name=YOUR_APP_SERVICE_ID&user=true"
```

## Step 2: Verify TMCP Server Configuration

### 2.1 Check TMCP Configuration
```bash
# Check TMCP configuration file
cat config/initializers/tmcp.rb

# Look for these key settings:
# matrix_hs_url: "https://your.matrix.server"
# matrix_hs_token: "YOUR_HOMESERVER_TOKEN" 
# matrix_appservice_token: "YOUR_APPSERVICE_TOKEN"
# matrix_appservice_id: "YOUR_APP_SERVICE_ID"
```

### 2.2 Verify Environment Variables
```bash
# Check environment variables
printenv | grep -E "MATRIX|TMCP"

# Should show:
# MATRIX_HS_URL=https://your.matrix.server
# MATRIX_HS_TOKEN=your_token_here
# MATRIX_ACCESS_TOKEN=your_access_token
# MATRIX_APPSERVICE_TOKEN=your_appservice_token
# TMCP_PRIVATE_KEY=your_private_key
```

## Step 3: Test Matrix Event Processing

### 3.1 Send Test Event to Synapse
```bash
# Send a test event to trigger TMCP processing
curl -X PUT "https://your.matrix.server/_matrix/app/v1/transactions/:txn_id" \
     -H "Authorization: Bearer YOUR_HOMESERVER_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
           "events": [
             {
               "type": "m.room.message",
               "room_id": "!testroom:your.matrix.server",
               "sender": "@testuser:your.matrix.server",
               "content": {
                 "body": "TMCP Test Message"
               }
             }
           ]
         }'
```

### 3.2 Check TMCP Server Logs
```bash
# Check for event processing in TMCP logs
tail -f log/production.log | grep -i "event\|matrix\|processing"

# Look for messages like:
# "Received Matrix event for room !testroom:your.matrix.server"
# "Processing event from user @testuser:your.matrix.server"
# "Successfully processed Matrix event"
```

### 3.3 Verify Event Processing Endpoint
```bash
# Test the Matrix event endpoint directly
curl -X PUT "https://your.tmcp.server/api/v1/matrix/events" \
     -H "Content-Type: application/json" \
     -d '{
           "events": [
             {
               "type": "m.room.message",
               "room_id": "!testroom:your.matrix.server",
               "sender": "@testuser:your.matrix.server",
               "content": {
                 "body": "Direct TMCP Test"
               }
             }
           ]
         }'
```

## Step 4: Verify Health and Status Endpoints

### 4.1 Health Check
```bash
# Check TMCP health endpoint
curl "https://your.tmcp.server/_matrix/app/v1/ping"

# Expected response: {"status": "ok"}
```

### 4.2 OAuth Endpoints
```bash
# Test OAuth authorize endpoint
curl "https://your.tmcp.server/api/v1/oauth/authorize"

# Test OAuth token endpoint  
curl -X POST "https://your.tmcp.server/api/v1/oauth/token" \
     -H "Content-Type: application/json" \
     -d '{
           "grant_type": "authorization_code",
           "code": "test_code",
           "redirect_uri": "https://your.tmcp.server/api/v1/oauth2/callback",
           "client_id": "your_client_id"
         }'
```

### 4.3 Wallet Endpoints
```bash
# Test wallet balance
curl "https://your.tmcp.server/api/v1/wallet/balance"

# Test wallet resolve
curl "https://your.tmcp.server/api/v1/wallet/resolve/@testuser:your.matrix.server"
```

### 4.4 Storage Endpoints
```bash
# Test storage endpoint
curl "https://your.tmcp.server/api/v1/storage"

# Test storage with key
curl "https://your.tmcp.server/api/v1/storage/test_key"
```

### 4.5 Payment Endpoints
```bash
# Test payment request
curl -X POST "https://your.tmcp.server/api/v1/payments/request" \
     -H "Content-Type: application/json" \
     -d '{
           "amount": 1000,
           "currency": "USD",
           "description": "Test payment"
         }'
```

## Step 5: Verify Room and User Registration

### 5.1 Create Test Room
```bash
# Create a test room via Matrix API
curl -X POST "https://your.matrix.server/_matrix/client/v3/createRoom" \
     -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
           "room_alias_name": "tmcp_test_room",
           "name": "TMCP Test Room",
           "visibility": "private"
         }'
```

### 5.2 Send Message to Test Room
```bash
# Send a message to trigger TMCP processing
curl -X PUT "https://your.matrix.server/_matrix/client/v3/rooms/!testroomid:your.matrix.server/send/m.room.message/12345" \
     -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
           "msgtype": "m.text",
           "body": "TMCP Room Test Message"
         }'
```

### 5.3 Check TMCP Processing
```bash
# Check TMCP logs for room processing
tail -f log/production.log | grep -i "room\|tmcp_test_room"
```

## Step 6: Advanced Verification

### 6.1 Check Application Service URL Accessibility
```bash
# Test if Synapse can reach your TMCP server
curl -I "https://your.tmcp.server/api/v1/matrix/events"

# Should return 200 OK
```

### 6.2 Verify Token Permissions
```bash
# Check token permissions in Synapse
curl -H "Authorization: Bearer YOUR_HOMESERVER_TOKEN" \
     "https://your.matrix.server/_synapse/admin/v1/registration_details"
```

### 6.3 Check Firewall Rules
```bash
# Test connectivity between Synapse and TMCP
telnet your.tmcp.server 443
# or
nc -zv your.tmcp.server 443
```

## Step 7: Troubleshooting Common Issues

### 7.1 Registration Failed
```bash
# Check Synapse configuration
curl -H "Authorization: Bearer YOUR_HOMESERVER_TOKEN" \
     "https://your.matrix.server/_synapse/admin/v1/appservice"

# Verify TMCP configuration
cat config/initializers/tmcp.rb

# Check network connectivity
ping your.tmcp.server
telnet your.tmcp.server 443
```

### 7.2 Events Not Processing
```bash
# Check TMCP logs for errors
tail -f log/production.log | grep -i "error\|failed\|exception"

# Verify room exists
curl -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
     "https://your.matrix.server/_matrix/client/v3/rooms/!testroomid:your.matrix.server"

# Verify namespace configuration
curl -H "Authorization: Bearer YOUR_HOMESERVER_TOKEN" \
     "https://your.matrix.server/_synapse/admin/v1/appservice/namespace?service_name=YOUR_APP_SERVICE_ID"
```

### 7.3 Authentication Issues
```bash
# Verify token validity
curl -H "Authorization: Bearer YOUR_HOMESERVER_TOKEN" \
     "https://your.matrix.server/_synapse/admin/v1/appservice"

# Check token scope
curl -H "Authorization: Bearer YOUR_HOMESERVER_TOKEN" \
     "https://your.matrix.server/_synapse/admin/v1/registration_details"
```

## Step 8: Final Verification Checklist

### ✅ Success Indicators
- Synapse shows your application service in the registration list
- TMCP logs show "Successfully registered with Synapse" messages  
- Matrix event endpoint responds to test requests (200 OK)
- Room/user namespace registration is confirmed
- Test events are processed by TMCP
- All health endpoints return 200 OK
- OAuth endpoints respond appropriately

### ❌ Failure Indicators
- Synapse does not show your application service
- TMCP logs show registration errors
- Matrix event endpoint returns 401/403/500 errors
- Namespace registration is missing
- Test events are not processed
- Health endpoints return errors

## Step 9: Production Readiness

### 9.1 Monitor in Production
```bash
# Monitor TMCP logs in production
tail -f log/production.log

# Monitor Synapse logs for application service activity
tail -f /path/to/synapse/logs/appservice.log
```

### 9.2 Test with Real Mini-Apps
```bash
# Deploy a test mini-app and verify it can authenticate
# Test payment flows
# Verify storage functionality
# Check Matrix event integration
```

By following these detailed verification steps, you can confidently confirm that your TMCP application service has successfully registered with your Synapse server and is ready for production use.