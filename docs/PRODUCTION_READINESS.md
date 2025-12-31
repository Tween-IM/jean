# TMCP Server Production Readiness Assessment & Deployment Guide

## Executive Summary

**Status: PARTIALLY PRODUCTION READY**

The TMCP server implementation covers approximately **70% of the PROTO.md specification**. Key functionality for wallet operations, payments, storage, and Matrix integration is implemented, but several critical production features require attention before deployment.

---

## 1. Production Readiness Assessment

### ✅ Implemented Features (Green)

| Feature | Status | Notes |
|---------|--------|-------|
| TEP Token Generation/Validation | ✅ Complete | RS256 JWT with all required claims |
| OAuth 2.0 Authorization Flow | ✅ Complete | PKCE support, scope validation |
| Wallet Balance API | ✅ Complete | Full response structure per PROTO |
| P2P Transfer Initiation | ✅ Complete | With idempotency support |
| Payment Processing | ✅ Complete | Request, authorize, refund, MFA |
| Storage API | ✅ Complete | CRUD + batch operations |
| Matrix Application Service | ✅ Complete | Users, rooms, transactions endpoints |
| Payment Event Publishing | ✅ Complete | All m.tween.payment.* events |
| Gift System | ✅ Complete | Group gifts with distribution |
| Circuit Breaker | ✅ Complete | Per-operation isolation |
| Rate Limiting | ✅ Complete | Rack::Attack configured |
| Error Handling | ✅ Complete | Standardized error responses |

### ⚠️ Partially Implemented (Yellow)

| Feature | Status | Gap |
|---------|--------|-----|
| MAS Integration | ⚠️ Partial | Client exists but no real API calls |
| External Account Linking | ⚠️ Partial | Mock implementation only |
| Wallet Funding/Withdrawals | ⚠️ Partial | Mock implementation only |
| MFA Verification | ⚠️ Partial | Stub implementation only |
| Batch User Resolution | ⚠️ Partial | Basic implementation, no caching |
| Scheduled Expiry Jobs | ⚠️ Partial | Not implemented |
| Webhook Signature Verification | ⚠️ Partial | Service exists but unused |

### ❌ Missing Features (Red)

| Feature | Status | Impact |
|---------|--------|--------|
| Real Wallet Service Integration | ❌ Missing | Critical - all wallet ops are mocks |
| Payment Signature Verification | ❌ Missing | Security requirement from PROTO |
| Webhook Endpoint | ❌ Missing | Required for wallet callbacks |
| Idempotency Store (Redis) | ❌ Missing | Currently uses Rails.cache |
| Scheduled Transfer Expiry | ❌ Missing | P2P transfers won't expire |
| Gift Expiry Processing | ❌ Missing | Gifts won't auto-expire |
| Production SSL/TLS Config | ❌ Missing | No certificate configuration |
| Log Aggregation | ❌ Missing | No structured logging |

---

## 2. Critical Production Issues

### 2.1 Mock Wallet Service (CRITICAL)

**Issue**: `app/services/wallet_service.rb` is entirely mocked.

**Risk**: Payment processing, balance queries, and transfers are fake.

**Required Action**:
```ruby
# Replace with actual wallet service client
# Example integration:
class WalletService
  def self.get_balance(user_id)
    # Call actual wallet API
    WalletApi::Client.new.balance_for(user_id)
  end
end
```

**Timeline**: Must be replaced before production.

---

### 2.2 No Payment Signature Verification (CRITICAL)

**Issue**: PROTO Section 7.2.5 requires ECDSA P-256 or RSA-2048 signatures.

**Current State**: No signature validation in `payments_controller.rb`.

**Required Action**:
```ruby
# In payments_controller.rb
def authorize
  signature = params[:signature]
  device_info = params[:device_info]
  
  # Verify client signature
  unless PaymentSignatureService.verify(
    payment_id,
    signature,
    device_info["public_key"]
  )
    render json: { error: "invalid_signature" }, status: :unauthorized
    return
  end
end
```

---

### 2.3 No Scheduled Job Processing (HIGH)

**Issue**: P2P transfers and gifts have expiry times but no background jobs to process them.

**Risk**: Transfers and gifts will never expire/auto-refund.

**Required Action**:
```ruby
# config/recurring.yml
p2p_transfer_expiry:
  class: P2PTransferExpiryJob
  queue: scheduled
  every: "5m"

gift_expiry:
  class: GiftExpiryJob
  queue: scheduled
  every: "5m"
```

---

### 2.4 Missing Webhook Endpoint (MEDIUM)

**Issue**: PROTO specifies wallet callback endpoint at `/api/v1/wallet/callback`.

**Current State**: Route exists but no controller.

**Required Action**:
```ruby
# app/controllers/api/v1/wallet_callback_controller.rb
class Api::V1::WalletCallbackController < ApplicationController
  skip_before_action :verify_authenticity_token
  
  def create
    # Verify webhook signature
    signature = request.headers["X-Webhook-Signature"]
    unless WebhookSecurityService.verify(request.body, signature)
      render json: { error: "invalid_signature" }, status: :unauthorized
      return
    end
    
    # Process callback
    WalletCallbackProcessor.call(params)
    
    render json: { received: true }
  end
end
```

---

## 3. Security Checklist

### 3.1 Authentication & Authorization

- [ ] TEP Token RSA private key properly secured (TMCP_PRIVATE_KEY env var)
- [ ] MAS client secrets secured in vault/secrets manager
- [ ] OAuth 2.0 PKCE enforced for all flows
- [ ] Scope validation on all protected endpoints
- [ ] Token introspection endpoint rate limited

### 3.2 Transport Security

- [ ] TLS 1.3 configured on load balancer
- [ ] HSTS header configured
- [ ] Certificate pinningoptional)
- [ for mobile clients ( ] CORS configured with allowed origins

### 3.3 Payment Security

- [ ] Hardware-backed key storage configured
- [ ] Payment signature verification implemented
- [ ] Idempotency keys stored in Redis with 24h TTL
- [ ] MFA challenge/verify flow tested
- [ ] Fraud detection configured

### 3.4 Data Security

- [ ] Database encryption at rest enabled
- [ ] Sensitive data (wallet IDs) not logged
- [ ] Rate limiting configured per PROTO spec
- [ ] Account lockout after failed attempts

---

## 4. Infrastructure Requirements

### 4.1 Required Environment Variables

```bash
# Critical - Must be set
export TMCP_PRIVATE_KEY="$(cat /path/to/private_key.pem)"
export MATRIX_API_URL="https://matrix.tween.example"
export MATRIX_HS_TOKEN="your_hs_token"
export MATRIX_ACCESS_TOKEN="your_as_token"
export SECRET_KEY_BASE="$(rails secret)"
export POSTGRES_PASSWORD="secure_password"

# Recommended
export TMCP_JWT_ISSUER="https://tmcp.tween.example"
export REDIS_URL="redis://redis.tween.example:6379/0"
export ALLOWED_ORIGINS="https://tween.example,https://app.tween.example"
export RAILS_LOG_LEVEL="info"
export RAILS_SERVE_STATIC_FILES="true"
```

### 4.2 Database Schema

```bash
# Run migrations
rails db:migrate

# Verify schema
rails db:schema:dump
```

Required tables (already created):
- `users` - Matrix user identities
- `mini_apps` - Mini-app registrations
- `miniapp_installations` - User app installations
- `storage_entries` - Mini-app storage
- `group_gifts` - Gift data
- `mfa_methods` - MFA credentials
- `oauth2_access_tokens` - Doorkeeper tokens

### 4.3 Redis Configuration

```yaml
# config/cache.yml
production:
  url: <%= ENV["REDIS_URL"] || "redis://localhost:6379/0" %>
  timeout: 5s
  pool: 10
  max_connections: 50
```

**Required Redis data**:
- Rate limiting counters
- Idempotency keys (24h TTL)
- Circuit breaker state
- Session cache

---

## 5. Matrix Homeserver Integration

### 5.1 Application Service Registration

Register TMCP server with Matrix homeserver:

```yaml
# homeserver.yaml
app_service_config_files:
  - /etc/matrix/tmcp-registration.yaml

# tmcp-registration.yaml
id: tween-miniapps
url: https://tmcp.tween.example
as_token: <GENERATED_AS_TOKEN>
hs_token: <HOMESERVER_MATCHING_TOKEN>
sender_localpart: _tmcp
namespaces:
  users:
    - exclusive: true
      regex: "@_tmcp_.*"
    - exclusive: true
      regex: "@ma_.*"
  aliases:
    - exclusive: true
      regex: "#_tmcp_.*"
  rooms: []
rate_limited: false
```

**Registration Command**:
```bash
# Generate registration
register_new_matrix_user --config /etc/matrix/homeserver.yaml \
  --user _tmcp_as --admin --password <secure_password>

# Get AS token from Synapse admin API
curl -X POST "https://matrix.tween.example/_synapse/admin/v1/register" \
  -H "Authorization: Bearer <admin_token>" \
  -d '{"user": "tmcp_as", "admin": true}'
```

### 5.2 Namespaces Required

| Namespace | Pattern | Purpose |
|-----------|---------|---------|
| Users | `@_tmcp_payments:.*` | Payment bot user |
| Users | `@_tmcp_gifts:.*` | Gift bot user |
| Users | `@ma_.*` | Mini-app virtual users |
| Room Aliases | `#_tmcp_.*` | Mini-app rooms |

---

## 6. Deployment Architecture

### 6.1 Recommended Architecture

```
+-----------------------------------------------------------------+
|                    Load Balancer (TLS 1.3)                       |
|                  Nginx / HAProxy / ALB                           |
+---------------------------+-------------------------------------+
                            |
+---------------------------v-------------------------------------+
|                 Application Servers (3+ nodes)                   |
|   +-----------------------------------------------------+       |
|   |  Rails 8.1.1 + Puma                                 |       |
|   |  - TMCP API Endpoints                               |       |
|   |  - OAuth 2.0 Server                                 |       |
|   |  - Matrix AS Proxy                                  |       |
|   |  - Webhook Handler                                  |       |
|   +-----------------------------------------------------+       |
|                          |                                      |
|          +---------------+---------------+                      |
|          v               v               v                      |
|   +----------+   +----------+   +----------+                    |
|   |PostgreSQL|   |  Redis   |   |  S3/FS   |                    |
|   |  Primary |   |  Cluster |   |  Storage |                    |
|   +----------+   +----------+   +----------+                    |
+-----------------------------------------------------------------+
                          |
+---------------------------v-------------------------------------+
|                 External Services                                |
|  +-------------+  +-------------+  +-------------------------+  |
|  |   Matrix    |  |    Wallet   |  |  MAS (Keycloak/         |  |
|  | Homeserver  |  |   Service   |  |  Dex)                   |  |
|  +-------------+  +-------------+  +-------------------------+  |
+-----------------------------------------------------------------+
```

### 6.2 Ansible Deployment (spantaleev/matrix-docker-ansible)

Based on the spantaleev/ansible-matrix playbook:

```yaml
# inventory/host_vars/tmcp.tween.example/vars.yml
matrix_tmcp_enabled: true
matrix_tmcp_container_image: registry.tween.example/tmcp-server:v1.5.0
matrix_tmcp_container_http_host_port: 8080

matrix_tmcp_container_environment:
  TMCP_PRIVATE_KEY: "{{ vault_tmcp_private_key }}"
  MATRIX_API_URL: "https://matrix.tween.example"
  MATRIX_HS_TOKEN: "{{ vault_matrix_hs_token }}"
  MATRIX_ACCESS_TOKEN: "{{ vault_matrix_access_token }}"
  SECRET_KEY_BASE: "{{ vault_secret_key_base }}"
  POSTGRES_PASSWORD: "{{ vault_postgres_password }}"
  REDIS_URL: "redis://redis.tween.example:6379/0"

matrix_tmcp_container_volumes:
  - "{{ matrix_sensitive_data_path }}/tmcp/private_key.pem:/run/secrets/tmcp_private_key:ro"

# Configure reverse proxy
matrix_nginx_proxy_proxy_tmcp_http_host_port: 8080
matrix_nginx_proxy_proxy_tmcp_https_host_port: 443
```

**Deployment Steps**:

```bash
# 1. Prepare vault password
echo "vault_password" > ~/.vault_password

# 2. Create encrypted vault
ansible-vault create inventory/host_vars/tmcp.tween.example/vault.yml
# Add all *_password and *_token variables

# 3. Run provisioning
ansible-playbook -i inventory/hosts matrix-docker-ansible-deploy.yml \
  --tags=tmcp \
  -e @inventory/host_vars/tmcp.tween.example/vault.yml

# 4. Register with Matrix homeserver
ansible-playbook -i inventory/hosts matrix-docker-ansible-deploy.yml \
  --tags=register-tmcp \
  -e @inventory/host_vars/tmcp.tween.example/vault.yml

# 5. Verify registration
curl -X GET "https://matrix.tween.example/_matrix/client/versions" \
  -H "Authorization: Bearer $(cat /matrix/secrets/tmcp_as_token)"
```

---

## 7. Monitoring & Observability

### 7.1 Health Check Endpoints

```ruby
# config/routes.rb
get "health/check", to: "health#check"

# app/controllers/health_controller.rb
class HealthController < ApplicationController
  def check
    checks = {
      database: ActiveRecord::Base.connection.execute("SELECT 1").present?,
      redis: Rails.cache.redis.present?,
      matrix: MatrixClient.health_check,
      wallet: WalletService.health_check
    }
    
    status = checks.values.all? ? :ok : :service_unavailable
    
    render json: {
      status: status,
      checks: checks,
      timestamp: Time.current.iso8601
    }, status: status
  end
end
```

### 7.2 Metrics (Prometheus)

```ruby
# lib/metrics.rb
class Metrics
  def self.record_payment(amount, currency, status)
    PrometheusMetrics[:payment_total].increment(
      labels: { currency: currency, status: status }
    )
  end
  
  def self.record_request(duration, endpoint, status)
    PrometheusMetrics[:http_request_duration].observe(
      duration,
      labels: { endpoint: endpoint, status: status }
    )
  end
  
  def self.circuit_breaker_state(name, state)
    PrometheusMetrics[:circuit_breaker_status].set(
      state == :open ? 1 : 0,
      labels: { name: name }
    )
  end
end
```

### 7.3 Recommended Alerts

| Alert | Severity | Condition |
|-------|----------|-----------|
| High Error Rate | P1 | >5% errors over 5min |
| Circuit Breaker Open | P1 | Any breaker open > 2min |
| Payment Processing Failures | P1 | >10% failures over 5min |
| Latency SLO Breach | P2 | p99 > 500ms for 10min |
| Database Connection Pool | P2 | >80% utilization |
| Redis Memory | P2 | >80% memory used |

---

## 8. Rollback Plan

### 8.1 Database Rollback

```bash
# Check last migration
rails db:migrate:status

# Rollback last migration (if it's safe)
rails db:rollback

# Or rollback to specific version
rails db:migrate:down VERSION=20241221144128
```

### 8.2 Application Rollback

```bash
# Docker/Kubernetes
kubectl rollout undo deployment/tmcp-server

# Or deploy previous image version
helm upgrade tmcp oci://registry.tween.example/charts/tmcp \
  --set image.tag=v1.4.9
```

### 8.3 Matrix AS Unregistration

```bash
# Remove AS registration
curl -X DELETE "https://matrix.tween.example/_matrix/client/r0/register/ephemeral" \
  -H "Authorization: Bearer <admin_token>"
```

---

## 9. Pre-Production Checklist

### Before First Deployment

- [ ] Replace all mock wallet service implementations with real API clients
- [ ] Implement payment signature verification
- [ ] Create scheduled jobs for transfer/gift expiry
- [ ] Configure Redis for idempotency (not Rails.cache)
- [ ] Set up webhook endpoint with signature verification
- [ ] Generate production TLS certificates
- [ ] Configure HSTS headers
- [ ] Set up log aggregation (ELK/Loki)
- [ ] Configure Prometheus metrics
- [ ] Set up PagerDuty/OpsGenie alerts
- [ ] Create runbook for common issues
- [ ] Conduct security review
- [ ] Load test with realistic traffic patterns
- [ ] Chaos engineering test (kill nodes, test recovery)

### Before Go-Live

- [ ] Register AS with production Matrix homeserver
- [ ] Update DNS records for tmcp.tween.example
- [ ] Configure production load balancer SSL
- [ ] Enable production rate limiting
- [ ] Verify all environment variables set
- [ ] Test backup/restore procedures
- [ ] Run integration tests against production Matrix
- [ ] Soft launch with internal users
- [ ] Monitor for 48 hours before full launch

---

## 10. Known Limitations

### 10.1 Current Implementation Gaps

1. **No Real Wallet Integration**: All wallet operations are mocked
2. **No External Bank Integration**: Funding/withdrawals mock only
3. **No Production MFA**: Transaction PIN/biometric not implemented
4. **No Fraud Detection**: Transaction scoring not implemented
5. **No Geographic Restrictions**: Not configured
6. **No Audit Logging**: Financial audit trail incomplete

### 10.2 Features Deferred to v2.0

- Device code OAuth flow (RFC 8628)
- Batch user resolution with efficient caching
- Gift distribution algorithms optimization
- WebView security enhancements
- Mini-app update management
- Client bootstrap protocol

---

## Conclusion

The TMCP server implementation provides a solid foundation for production deployment but requires **replacement of mock wallet services** and **implementation of payment signature verification** before it can safely process real financial transactions.

**Recommended Go-Live Timeline**:
- **Week 1-2**: Replace wallet service mocks
- **Week 3**: Implement payment signatures
- **Week 4**: Security audit & load testing
- **Week 5**: Staging deployment & testing
- **Week 6**: Production deployment

**Go-Live Criteria**:
- [ ] All mock wallet services replaced
- [ ] Payment signature verification implemented
- [ ] All tests passing (129/129)
- [ ] Security audit passed
- [ ] Load test passed (1000 RPS sustained)
- [ ] Runbook created and tested
- [ ] On-call rotation established
