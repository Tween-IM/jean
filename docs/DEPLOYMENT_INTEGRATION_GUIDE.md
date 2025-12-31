# TMCP Server Integration Guide for Ansible-Based Matrix Deployment

This guide covers integrating the TMCP server with a Matrix homeserver deployed using the [spantaleev/ansible-matrix](https://github.com/spantaleev/matrix-docker-ansible) playbook.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [TMCP Server Configuration](#tmcp-server-configuration)
4. [Matrix Homeserver Integration](#matrix-homeserver-integration)
5. [SSL/TLS Configuration](#ssltls-configuration)
6. [Testing the Integration](#testing-the-integration)
7. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### System Requirements

- Ansible 2.14+
- Python 3.10+
- Access to a server running Debian/Ubuntu with:
  - At least 4GB RAM
  - 2 CPU cores
  - 50GB storage
  - Root SSH access

### Pre-installed Matrix Server

This guide assumes you already have a working Matrix homeserver deployed using:

```bash
git clone https://github.com/spantaleev/matrix-docker-ansible.git
cd matrix-docker-ansible
```

---

## Initial Setup

### 1. Clone and Configure Ansible

```bash
# Clone the playbook
git clone https://github.com/spantaleev/matrix-docker-ansible.git
cd matrix-docker-ansible

# Create inventory directory structure
mkdir -p inventory/host_vars
touch inventory/hosts
```

### 2. Configure Inventory

Edit `inventory/hosts`:

```ini
[matrix_servers]
tmcp.tween.example ansible_host=203.0.113.50 ansible_user=root

[all:vars]
ansible_python_interpreter=/usr/bin/python3
```

### 3. Create Host Variables

Create `inventory/host_vars/tmcp.tween.example/vars.yml`:

```yaml
---
# Matrix Server Configuration
matrix_domain: tween.example
matrix_ssl_letsencrypt_email: admin@tween.example

# Container Configuration
matrix_dockerNetworkingdnsservers:
  - 8.8.8.8
  - 8.8.4.4

# PostgreSQL Configuration
matrix_postgres_connection_password: "{{ vault_matrix_postgres_password }}"

# TMCP Server Configuration
matrix_tmcp_enabled: true
matrix_tmcp_container_image: registry.tween.example/tmcp-server:latest
matrix_tmcp_container_http_host_port: 8080
matrix_tmcp_container_https_host_port: 8443

# TMCP Environment Variables
matrix_tmcp_container_environment:
  TMCP_PRIVATE_KEY: "{{ vault_tmcp_private_key }}"
  MATRIX_API_URL: "https://matrix.tween.example"
  MATRIX_HS_TOKEN: "{{ vault_matrix_hs_token }}"
  MATRIX_ACCESS_TOKEN: "{{ vault_matrix_access_token }}"
  SECRET_KEY_BASE: "{{ vault_secret_key_base }}"
  POSTGRES_PASSWORD: "{{ vault_matrix_postgres_password }}"
  REDIS_URL: "redis://redis.tween.example:6379/0"
  RAILS_ENV: "production"
  RAILS_LOG_LEVEL: "info"

# Volume Mounts
matrix_tmcp_container_volumes:
  - "{{ matrix_sensitive_data_path }}/tmcp/private_key.pem:/run/secrets/tmcp_private_key:ro"
  - "{{ matrix_sensitive_data_path }}/tmcp/certs:/run/secrets/certs:ro"

# Resource Limits
matrix_tmcp_container_resource_limits:
  cpus: '2.0'
  memory: 4G

# Nginx Proxy Configuration
matrix_nginx_proxy_proxy_tmcp_http_host_port: 8080
matrix_nginx_proxy_proxy_tmcp_https_host_port: 443

# Enable additional services
matrix_metrics_enabled: true
matrix_nginx_proxy_enabled: true
```

---

## TMCP Server Configuration

### 1. Create Encrypted Vault

Create a secure vault for sensitive variables:

```bash
# Create vault password file
echo "your-secure-vault-password" > ~/.vault_password

# Create vault file
ansible-vault create inventory/host_vars/tmcp.tween.example/vault.yml
```

Add the following to `vault.yml`:

```yaml
$ANSIBLE_VAULT;1.1;AES256
# TMCP Server Secrets
vault_tmcp_private_key: |
  -----BEGIN RSA PRIVATE KEY-----
  ... (your actual private key) ...
  -----END RSA PRIVATE KEY-----

vault_matrix_postgres_password: "secure-postgres-password"
vault_matrix_hs_token: "your-homeserver-token"
vault_matrix_access_token: "your-as-access-token"
vault_secret_key_base: "$(rails secret)"
```

### 2. Generate Application Service Registration

The playbook will auto-generate AS registration, but you can also create it manually:

```yaml
# roles/custom/tmcp/templates/tmcp-registration.yaml.j2
id: tween-miniapps
url: https://tmcp.tween.example
as_token: {{ matrix_tmcp_as_token }}
hs_token: {{ matrix_tmcp_hs_token }}
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

---

## Matrix Homeserver Integration

### 1. Configure Application Service Registration

Add to your `group_vars/all/main.yml`:

```yaml
# Enable Application Service support
matrix_app_service_support_enabled: true

# Configure AS registration path
matrix_app_service_registration_path: "{{ matrix_config_dir_path }}/tmcp-registration.yaml"
```

### 2. Register the TMCP Application Service

The playbook will automatically:
1. Generate AS tokens
2. Create registration file
3. Configure Synapse to load the AS
4. Restart the homeserver

### 3. Verify AS Registration

After deployment, verify the AS is registered:

```bash
# SSH into the server
ssh root@tmcp.tween.example

# Check Synapse logs
docker logs matrix-synapse 2>&1 | grep -i "app_service"

# Check AS is recognized
curl -X GET "https://matrix.tween.example/_matrix/client/versions" \
  -H "Authorization: Bearer $AS_ACCESS_TOKEN"
```

---

## SSL/TLS Configuration

### 1. Let's Encrypt Certificates

The playbook automatically configures Let's Encrypt. If using custom certificates:

```yaml
# inventory/host_vars/tmcp.tween.example/vars.yml

# Use custom certificates
matrix_ssl_enabled: true
matrix_ssl_cert_path: "/path/to/cert.pem"
matrix_ssl_key_path: "/path/to/key.pem"
matrix_ssl_ca_cert_path: "/path/to/ca.pem"

# Or provision via Let's Encrypt
matrix_ssl_letsencrypt_enable: true
matrix_ssl_letsencrypt_email: "admin@tween.example"
matrix_ssl_letsencrypt_agree_tos: true
```

### 2. Configure TLS in TMCP Server

```yaml
# In vault.yml or environment
FORCE_SSL: "true"
ALLOWED_ORIGINS: "https://tween.example,https://app.tween.example"
```

### 3. HSTS Configuration

HSTS is enabled by default. To customize:

```yaml
matrix_nginx_proxy_hsts_max_age: 31536000
matrix_nginx_proxy_hsts_include_subdomains: true
matrix_nginx_proxy_hsts_preload: true
```

---

## Testing the Integration

### 1. Run the Playbook

```bash
# First-time setup
ansible-playbook -i inventory/hosts setup.yml --ask-vault-password

# Deploy Matrix and TMCP
ansible-playbook -i inventory/hosts matrix-docker-ansible-deploy.yml \
  --tags=tmcp \
  --ask-vault-password

# Or deploy everything
ansible-playbook -i inventory/hosts matrix-docker-ansible-deploy.yml \
  --ask-vault-password
```

### 2. Verify TMCP Server Health

```bash
# Health check
curl https://tmcp.tween.example/health/check

# Expected response:
{
  "status": "ok",
  "checks": {
    "database": true,
    "redis": true,
    "matrix": true,
    "wallet": true
  },
  "timestamp": "2025-12-31T00:00:00Z"
}
```

### 3. Test Matrix Application Service

```bash
# Test AS user query
curl "https://matrix.tween.example/_matrix/app/v1/users/@alice:tween.example" \
  -H "Authorization: Bearer $AS_HS_TOKEN"

# Expected: {} with 200 status if user exists
# Expected: {} with 404 status if user doesn't exist
```

### 4. Test OAuth Flow

```bash
# Get authorization URL
curl "https://matrix.tween.example/api/v1/oauth/authorize?"\
  "response_type=code&"\
  "client_id=ma_test&"\
  "redirect_uri=https://app.tween.example/callback&"\
  "scope=user:read%20wallet:pay&"\
  "state=xyz"

# Should redirect to login page
```

### 5. Test Wallet Resolution

```bash
# Resolve user to wallet
curl "https://tmcp.tween.example/api/v1/wallet/resolve/@alice:tween.example" \
  -H "Authorization: Bearer $TEP_TOKEN"

# Expected response:
{
  "user_id": "@alice:tween.example",
  "wallet_id": "tw_alice_123",
  "wallet_status": "active",
  "payment_enabled": true
}
```

---

## Troubleshooting

### Common Issues

#### 1. AS Not Registering

**Symptom**: AS doesn't appear in Synapse logs.

**Solution**:
```bash
# Check registration file
docker exec matrix-synapse cat /matrix/synapse/app-service-registrations/tmcp-registration.yaml

# Verify format is correct YAML
python3 -c "import yaml; yaml.safe_load(open('/path/to/registration.yaml'))"

# Restart synapse
docker restart matrix-synapse
```

#### 2. TLS Certificate Issues

**Symptom**: SSL handshake failures.

**Solution**:
```bash
# Check certificate expiration
openssl s_client -connect tmcp.tween.example:443 -servername tmcp.tween.example | \
  openssl x509 -noout -dates

# Renew Let's Encrypt certificate
docker exec matrix-certbot renew --quiet
docker restart matrix-nginx-proxy
```

#### 3. TMCP Container Won't Start

**Symptom**: Container exits immediately with error.

**Solution**:
```bash
# Check container logs
docker logs matrix-tmcp

# Common issues:
# - Missing environment variables
# - Invalid private key format
# - Database connection refused

# Verify environment
docker exec matrix-tmcp env | grep TMCP
```

#### 4. Rate Limiting Issues

**Symptom**: Requests returning 429.

**Solution**:
```yaml
# Increase rate limits in vars.yml
matrix_tmcp_rate_limits:
  oauth_token: 100  # Increased from 60
  wallet_balance: 60  # Increased from 30
  wallet_transactions: 40  # Increased from 20
  p2p_transfer: 20  # Increased from 10
  payment_request: 40  # Increased from 20
```

#### 5. Database Connection Issues

**Symptom**: "ActiveRecord::ConnectionNotEstablished"

**Solution**:
```bash
# Check database health
docker exec matrix-postgres pg_isready -U postgres

# Verify connection string
docker exec matrix-tmcp cat /etc/environment | grep DATABASE_URL

# Recreate database schema
docker exec matrix-tmcp rails db:migrate
```

### Useful Commands

```bash
# View TMCP logs
docker logs -f matrix-tmcp

# View Matrix Synapse logs
docker logs -f matrix-synapse

# Restart TMCP
docker restart matrix-tmcp

# Restart Synapse (will disconnect users)
docker restart matrix-synapse

# Check running containers
docker ps | grep matrix

# View TMCP metrics
curl localhost:8080/metrics

# Test database connection
docker exec matrix-tmcp rails dbconsole
```

### Log Analysis

```bash
# Search for errors in TMCP logs
docker logs matrix-tmcp 2>&1 | grep -i error

# Search for wallet-related logs
docker logs matrix-tmcp 2>&1 | grep -i wallet

# Search for authentication issues
docker logs matrix-tmcp 2>&1 | grep -i "unauthorized\|forbidden"

# Search for Matrix API calls
docker logs matrix-tmcp 2>&1 | grep -i "matrix.*api"
```

---

## Security Considerations

### 1. Firewall Configuration

```bash
# Allow only HTTPS (443) and SSH (22)
ufw allow 22/tcp
ufw allow 443/tcp
ufw enable
```

### 2. Container Security

The playbook configures security options by default. To enhance:

```yaml
matrix_tmcp_container_security_options:
  - "no-new-privileges:true"
  - "seccomp:unconfined"  # Or use a custom seccomp profile
```

### 3. Secrets Management

Never commit secrets to version control:

```bash
# Add to .gitignore
*.pem
vault.yml
*.key

# Use Ansible Vault for all secrets
ansible-vault edit inventory/host_vars/tmcp.tween.example/vault.yml
```

### 4. Monitoring for Security Events

```yaml
# Enable detailed logging
matrix_tmcp_container_environment:
  RAILS_LOG_LEVEL: "debug"
  LOG_LEVEL: "debug"

# Monitor failed authentication attempts
docker logs matrix-tmcp 2>&1 | grep "401 Unauthorized"
```

---

## Backup and Recovery

### 1. Database Backup

```bash
# Create backup
docker exec matrix-postgres pg_dump -U postgres matrix > backup_$(date +%Y%m%d).sql

# Automated backup (add to crontab)
0 2 * * * docker exec matrix-postgres pg_dump -U postgres matrix | gzip > /backups/matrix_$(date +\%Y\%m\%d).sql.gz
```

### 2. Restore from Backup

```bash
# Restore database
docker exec -i matrix-postgres psql -U postgres matrix < backup_20251231.sql
```

### 3. Configuration Backup

```bash
# Backup Ansible inventory
tar -czvf ansible-inventory-$(date +%Y%m%d).tar.gz inventory/

# Backup TLS certificates
cp -r /etc/letsencrypt /backup/letsencrypt-$(date +%Y%m%d)
```

---

## Performance Tuning

### 1. Container Resources

```yaml
matrix_tmcp_container_resource_limits:
  cpus: '4.0'
  memory: 8G

matrix_tmcp_container_resource_requests:
  cpus: '2.0'
  memory: 4G
```

### 2. Database Connection Pool

```yaml
# In database.yml
production:
  pool: 50
  timeout: 30
  reconnect: true
```

### 3. Redis Configuration

```yaml
# In config/environments/production.rb
config.cache_store = :redis_cache_store,
  url: ENV["REDIS_URL"],
  namespace: "tmcp",
  pool_size: 10,
  pool_timeout: 5,
  expires_in: 1.hour
```

---

## Conclusion

This guide provides the necessary steps to integrate the TMCP server with a Matrix homeserver deployed via Ansible. For additional support:

- **TMCP Issues**: Open issue at `/config/workspace/jean/issues`
- **Matrix Issues**: See [matrix-docker-ansible documentation](https://github.com/spantaleev/matrix-docker-ansible)
- **Synapse Issues**: See [Matrix Synapse documentation](https://matrix-org.github.io/synapse/)
