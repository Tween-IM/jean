# TMCP Server Deployment Checklist

## Pre-Deployment Checklist

### 1. Domain and SSL Certificates
- [ ] Domain `tmcp.example.com` points to your server
- [ ] SSL certificate installed for `tmcp.example.com`
- [ ] SSL certificate installed for `auth.tween.im` (MAS)
- [ ] DNS records configured

### 2. Infrastructure Requirements
- [ ] PostgreSQL database server running
- [ ] Redis server running
- [ ] Ruby 3.4.4 installed
- [ ] Bundler installed
- [ ] Nginx installed and configured

### 3. Environment Variables Prepared
- [ ] `SECRET_KEY_BASE` generated
- [ ] `TMCP_PRIVATE_KEY` available
- [ ] `MAS_CLIENT_SECRET` generated
- [ ] `MATRIX_HS_TOKEN` from Synapse
- [ ] Database passwords set

## Deployment Steps

### Step 1: Matrix Homeserver Configuration
```bash
# Add to Synapse homeserver.yaml
app_service_config:
  - id: tmcp-server
    url: https://tmcp.example.com
    hs_token: YOUR_HS_TOKEN
    sender_localpart: _tmcp
    namespaces:
      users:
        - exclusive: ["@_tmcp.*:.*"]
      aliases:
        - exclusive: ["#tmcp_.*:.*"]
    rate_limited: false
```

### Step 2: MAS Configuration
- [ ] Deploy `mas-config.yaml` to MAS server
- [ ] Restart MAS service
- [ ] Verify MAS endpoints are accessible

### Step 3: TMCP Server Deployment
```bash
# Clone repository
git clone https://github.com/mona-chen/jean.git /opt/tmcp
cd /opt/tmcp

# Install dependencies
bundle install --deployment --without development test

# Configure environment
cp .env.example .env
# Edit .env with production values

# Setup database and seed official mini-apps from YAML
rails db:create db:migrate db:seed RAILS_ENV=production

# The db:seed command now automatically:
# - Loads mini-apps from config/mini_apps.yml
# - Approves official mini-apps
# - Creates OAuth applications for approved mini-apps

# Precompile assets
rails assets:precompile RAILS_ENV=production

# Start service
systemctl enable tmcp
systemctl start tmcp
```

### Step 4: Nginx Configuration
- [ ] Deploy Nginx config for `tmcp.example.com`
- [ ] Enable SSL/TLS
- [ ] Configure upstream to Puma socket
- [ ] Test SSL certificate

### Step 5: Verification Tests

#### Test TMCP Server Health
```bash
curl https://tmcp.example.com/health/check
# Expected: {"status": "ok"}
```

#### Test Matrix AS Registration
```bash
curl https://tmcp.example.com/_matrix/app/v1/ping
# Expected: {}
```

#### Test MAS Client Authentication
```bash
# Test client credentials grant
curl -X POST https://auth.tween.im/oauth2/token \
  -u tmcp-server:YOUR_CLIENT_SECRET \
  -d "grant_type=client_credentials"
# Expected: access_token response
```

#### Test Official Mini-Apps
```bash
# List all mini-apps
curl https://tmcp.example.com/api/v1/mini-apps
# Should show TweenPay, TweenShop, TweenChat, TweenGames

# Test TweenPay OAuth
curl -X POST https://tmcp.example.com/api/v1/oauth/authorize \
  -d "client_id=ma_tweenpay&response_type=code&scope=user:read wallet:balance"
# Should redirect to MAS authorization
```

#### Test TEP Token Issuance
```bash
# Get a Matrix token first, then exchange
curl -X POST https://tmcp.example.com/api/v1/oauth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=urn:ietf:params:oauth:grant-type:token-exchange&subject_token=MATRIX_TOKEN&client_id=ma_test&client_secret=CLIENT_SECRET&scope=user:read"
```

## Troubleshooting

### MAS Client Authentication Fails
1. Check MAS configuration file syntax
2. Verify client_secret matches TMCP environment
3. Restart MAS service after config changes
4. Check MAS logs for errors

### Matrix AS Registration Fails
1. Verify HS_TOKEN is correct
2. Check Synapse homeserver.yaml syntax
3. Restart Synapse after config changes
4. Test AS ping endpoint

### TMCP Server Won't Start
1. Check Ruby version compatibility
2. Verify all environment variables set
3. Check database connectivity
4. Review Rails logs

### SSL Certificate Issues
1. Verify certificate paths in Nginx config
2. Check certificate validity dates
3. Test certificate chain
4. Restart Nginx after certificate updates

## Monitoring

### Log Files
- TMCP: `journalctl -u tmcp -f`
- Nginx: `/var/log/nginx/tmcp.access.log`
- MAS: `journalctl -u mas -f`

### Health Checks
- TMCP: `https://tmcp.example.com/health/check`
- MAS: `https://auth.tween.im/.well-known/openid-configuration`

### Performance Metrics
- Database connections
- Redis memory usage
- Response times
- Error rates

## Rollback Plan

If deployment fails:

1. Stop TMCP service: `systemctl stop tmcp`
2. Remove Nginx config: `rm /etc/nginx/sites-enabled/tmcp.conf`
3. Reload Nginx: `nginx -s reload`
4. Restore previous AS config in Synapse
5. Restart Synapse

## Security Checklist

- [ ] All secrets in environment variables (not code)
- [ ] SSL/TLS enabled everywhere
- [ ] Firewall configured properly
- [ ] Database access restricted
- [ ] Logs monitored for security events
- [ ] Regular security updates scheduled