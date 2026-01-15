# TMCP Server Deployment Guide

## Overview

This guide covers the complete deployment of TMCP Server as a Matrix Application Service with MAS (Matrix Authentication Service) integration, using the Spantalev Ansible playbook for deployment.

## Prerequisites

- Matrix homeserver (Synapse) with Application Service support
- Matrix Authentication Service (MAS) instance
- PostgreSQL database
- Redis instance
- Domain name (tmcp.example.com)
- SSL certificates
- Ansible (Spantalev)

## Step 1: Register TMCP Server with Matrix Homeserver

### Option A: Synapse Configuration File (Recommended)

Add to your Synapse `homeserver.yaml`:

```yaml
app_service_config:
  - id: tmcp-server
    url: https://tmcp.example.com
    as_token: "54280d605e23adf6bd5d66ee07a09196dbab0bd87d35f8ecc1fd70669f709502"
    hs_token: "874542cda496ffd03f8fd283ad37d8837572aad0734e92225c5f7fffd8c91bd1"
    sender_localpart: _tmcp
    namespaces:
      users:
        - exclusive: ["@_tmcp.*:.*"]
      aliases:
        - exclusive: ["#tmcp_.*:.*"]
    rate_limited: false
```

**Token Configuration:**
- `as_token`: Used by homeserver to authenticate with TMCP Server
- `hs_token`: Used by TMCP Server to authenticate with homeserver
- Set `MATRIX_HS_TOKEN=874542cda496ffd03f8fd283ad37d8837572aad0734e92225c5f7fffd8c91bd1` in TMCP Server environment

### Option B: Database Registration

Connect to Synapse PostgreSQL and run:

```sql
INSERT INTO application_services_state (id, url, hs_token, sender_localpart, namespaces, rate_limited)
VALUES (
  'tmcp-server',
  'https://tmcp.example.com',
  'YOUR_HS_TOKEN',
  '_tmcp',
  '{"users": ["@_tmcp.*:.*"], "aliases": ["#tmcp.*:.*"]}',
  false
);
```

**Required Information:**
- `url`: Your TMCP Server public URL
- `hs_token`: Synapse admin access token
- `sender_localpart`: `_tmcp` (AS user will be `@_tmcp:tmcp.example`)
- `namespaces`: Exclusive patterns for AS-controlled users and aliases
- `rate_limited`: `false` (critical for TMCP performance)

## Step 2: Configure MAS Client Registration

### Method A: MAS Admin UI

1. Login to MAS admin: `https://auth.tween.im/admin`
2. Navigate to: **Clients** → **Manage Clients**
3. Click **Create New Client**
4. Configure:
   - **Client ID**: `tmcp-server`
   - **Client Name**: `TMCP Server`
   - **Grant Types**:
     - ✓ `urn:ietf:params:oauth:grant-type:token-exchange`
     - ✓ `urn:ietf:params:oauth:grant-type:device_code`
     - ✓ `refresh_token`
     - ✓ `client_credentials`
     - ✓ `authorization_code`
   - **Scopes**: `urn:matrix:org.matrix.msc2967.client:api:*`
   - **Redirect URIs**: `https://tmcp.example.com/api/v1/oauth/callback`
   - **Auth Method**: `client_secret_post`
   - **Client Secret**: Generate secure 32-char secret

### Method B: MAS API

```bash
curl -X POST https://auth.tween.im/admin/client \
  -H "Authorization: Bearer YOUR_MAS_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "client_id": "tmcp-server",
    "client_secret": "YOUR_MAS_CLIENT_SECRET",
    "redirect_uris": ["https://tmcp.tween.im/api/v1/oauth/callback"],
    "grant_types": [
      "urn:ietf:params:oauth:grant-type:token-exchange",
      "refresh_token",
      "client_credentials"
    ],
    "scope": "urn:matrix:org.matrix.msc2967.client:api:*",
    "client_auth_method": "client_secret_post"
  }'
```

## Step 3: Environment Configuration

Create production environment variables:

```bash
# Base Configuration
RAILS_ENV=production
BASE_URL=https://tmcp.example.com

# Database
DATABASE_URL=postgresql://tmcp:secure_password@db:5432/tmcp
REDIS_URL=redis://localhost:6379

# Security
SECRET_KEY_BASE=$(rails secret)
TMCP_PRIVATE_KEY=$(cat secrets/tmcp_private_key.txt)
TMCP_JWT_ISSUER=https://tmcp.example.com
TMCP_JWT_KEY_ID=tmcp-2025-01

# MAS Integration
MAS_CLIENT_ID=tmcp-server
MAS_CLIENT_SECRET=your_generated_secret_here
MAS_URL=https://auth.tween.im/oauth2
MAS_TOKEN_URL=https://auth.tween.im/oauth2/token
MAS_INTROSPECTION_URL=https://auth.tween.im/oauth2/introspect
MAS_REVOCATION_URL=https://auth.tween.im/oauth2/revoke

# Matrix Homeserver
MATRIX_HS_TOKEN=874542cda496ffd03f8fd283ad37d8837572aad0734e92225c5f7fffd8c91bd1
MATRIX_API_URL=https://matrix.tween.example
MATRIX_ACCESS_TOKEN=mas_generated_token

# Optional
FORCE_SSL=true
ALLOWED_ORIGINS=https://matrix.tween.example
REDIS_URL=redis://localhost:6379
```

## Step 4: Spantalev Ansible Deployment

### Installation

```bash
# Install Ansible
pip3 install ansible-core ansible[azure]

# Verify installation
ansible --version
```

### Create Ansible Inventory

Create `ansible/inventory/hosts`:

```ini
[matrix-hs]
ansible_host=your-homeserver.com
ansible_user=root
ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[tmcp-server]
ansible_host=tmcp.example.com
ansible_user=deploy
ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[database]
ansible_host=db.example.com
ansible_user=postgres
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

### Deploy MAS (Matrix Authentication Service)

Create `ansible/deploy-mas.yml`:

```yaml
---
- name: Deploy Matrix Authentication Service (MAS)
  hosts: [matrix-hs]
  become: yes
  gather_facts: yes

  vars:
    mas_client_id: "tmcp-server"
    mas_client_secret: "{{ lookup('env', 'MAS_CLIENT_SECRET') }}"
    mas_database_url: "postgresql://mas:mas_password@db:5432/mas"
    tmcp_callback_url: "https://tmcp.example.com/api/v1/oauth/callback"

  handlers:
    - name: Restart MAS service
      systemd:
        name: mas
        state: restarted

  tasks:
    - name: Deploy MAS configuration
      debug:
        msg: "Deploying MAS for TMCP Server..."

    - name: Create MAS config directory
      file:
        path: /etc/mas
        state: directory
        mode: '0755'

    - name: Copy MAS config file
      copy:
        src: mas-config.yaml
        dest: /etc/mas/mas.yaml
        owner: root
        group: root
        mode: '0644'

    - name: Set proper permissions
      file:
        path: /etc/mas/mas.yaml
        mode: '0640'
        owner: root
        group: root

    - name: Install MAS dependencies
      package:
        name: ['postgresql-client', 'nginx']
        state: present

    - name: Restart MAS service
      systemd:
        name: mas
        daemon_reload: yes
```

Deploy MAS:

```bash
ansible-playbook -i ansible/inventory/hosts ansible/deploy-mas.yml \
  -e "MAS_CLIENT_SECRET=$(openssl rand -base64 24)"
```

### Deploy TMCP Server

Create `ansible/deploy-tmcp.yml`:

```yaml
---
- name: Deploy TMCP Server
  hosts: [tmcp-server]
  become: yes

  vars_files:
    - ansible/env_vars.yml

  vars:
    rails_env: production
    base_url: https://tmcp.example.com

  handlers:
    - name: Restart TMCP
      systemd:
        name: tmcp
        state: restarted

  pre_tasks:
    - name: Display deployment info
      debug:
        msg: |
          Deploying TMCP Server to production
          Environment: {{ rails_env }}
          URL: {{ base_url }}

  tasks:
    - name: Update git repository
      git:
        repo: https://github.com/mona-chen/jean.git
        dest: /opt/tmcp
        force: yes
        version: main

    - name: Install Ruby dependencies
      bundler:
        executable: bundle
        chdir: /opt/tmcp
        gemfile: Gemfile

    - name: Install PostgreSQL client
      apt:
        name: ['postgresql-client', 'libpq-dev']
        state: present
        update_cache: yes

    - name: Create .env file
      copy:
        content: |
          RAILS_ENV={{ rails_env }}
          BASE_URL={{ base_url }}
          DATABASE_URL=postgresql://tmcp:tmcp_password@db:5432/tmcp
          REDIS_URL=redis://localhost:6379
          SECRET_KEY_BASE={{ lookup('env', 'SECRET_KEY_BASE') }}
          TMCP_PRIVATE_KEY=$(cat /opt/tmcp/secrets/tmcp_private_key.txt)
          TMCP_JWT_ISSUER={{ base_url }}
          TMCP_JWT_KEY_ID=tmcp-2025-01
          MAS_CLIENT_ID=tmcp-server
          MAS_CLIENT_SECRET={{ lookup('env', 'MAS_CLIENT_SECRET') }}
          MAS_URL=https://auth.tween.im/oauth2
          MAS_TOKEN_URL=https://auth.tween.im/oauth2/token
          MAS_INTROSPECTION_URL=https://auth.tween.im/oauth2/introspect
          MAS_REVOCATION_URL=https://auth.tween.im/oauth2/revoke
          MATRIX_HS_TOKEN={{ lookup('env', 'MATRIX_HS_TOKEN') }}
        dest: /opt/tmcp/.env

    - name: Setup database
      shell: |
        cd /opt/tmcp && rails db:create db:migrate RAILS_ENV=production
      environment:
        RAILS_ENV: production

    - name: Create systemd service
      copy:
        content: |
          [Unit]
          Description=TMCP Server Application Service
          After=network.target
          Wants=postgresql.service

          [Service]
          Type=simple
          User=tmcp
          WorkingDirectory=/opt/tmcp
          Environment=RAILS_ENV=production
          EnvironmentFile=/opt/tmcp/.env
          ExecStart=/usr/local/bin/bundle exec puma -C config/puma.rb
          Restart=always
          RestartSec=10

          [Install]
          WantedBy=multi-user.target
        dest: /etc/systemd/system/tmcp.service
        mode: '0644'

    - name: Enable and start TMCP
      systemd:
        name: tmcp
        enabled: yes
        state: started

    - name: Configure Nginx reverse proxy
      template:
        src: ansible/nginx-tmcp.conf.j2
        dest: /etc/nginx/sites-available/tmcp.conf
        mode: '0644'
      notify:
        - Reload Nginx

    - name: Enable site
      file:
        src: /etc/nginx/sites-available/tmcp.conf
        dest: /etc/nginx/sites-enabled/tmcp.conf
        state: link
      notify:
        - Reload Nginx

  handlers:
    - name: Reload Nginx
      systemd:
        name: nginx
        state: reloaded
```

Create `ansible/env_vars.yml`:

```yaml
# Environment variables for TMCP deployment
secret_key_base: "{{ lookup('env', 'SECRET_KEY_BASE') }}"
mas_client_secret: "{{ lookup('env', 'MAS_CLIENT_SECRET') }}"
matrix_hs_token: "{{ lookup('env', 'MATRIX_HS_TOKEN') }}"
tmcp_private_key: "{{ lookup('file', '/opt/tmcp/secrets/tmcp_private_key.txt') }}"
```

Create `ansible/nginx-tmcp.conf.j2`:

```nginx
# TMCP Server Nginx Configuration

upstream tmcp {
  server unix:///var/run/tmcp/puma.sock;
}

server {
  listen 80;
  server_name tmcp.example.com;
  return 301 https://$server_name$request_uri;
}

server {
  listen 443 ssl http2;
  server_name tmcp.example.com;

  # SSL Configuration
  ssl_certificate /etc/ssl/certs/tmcp.crt;
  ssl_certificate_key /etc/ssl/private/tmcp.key;
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
  ssl_prefer_server_ciphers off;

  # Security headers
  add_header X-Frame-Options DENY;
  add_header X-Content-Type-Options nosniff;
  add_header X-XSS-Protection "1; mode=block";
  add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

  # Logs
  access_log /var/log/nginx/tmcp.access.log;
  error_log /var/log/nginx/tmcp.error.log;

  location / {
    proxy_pass http://tmcp;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_redirect off;

    # WebSocket support for real-time features
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";

    # Timeouts
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
  }

  # Health check endpoint
  location /health/check {
    proxy_pass http://tmcp;
    access_log off;
  }

  # Matrix AS endpoints
  location /_matrix/ {
    proxy_pass http://tmcp;
    proxy_set_header Authorization $http_authorization;
  }
}
```

Deploy TMCP Server:

```bash
ansible-playbook -i ansible/inventory/hosts ansible/deploy-tmcp.yml
```

## Step 5: Verification

### Test TMCP Server Health

```bash
curl https://tmcp.example.com/health/check
# Expected: {"status": "ok"}
```

### Test Matrix AS Registration

```bash
curl https://tmcp.example.com/_matrix/app/v1/ping
# Expected: {}
```

### Test MAS Integration

```bash
# Get a Matrix token from your homeserver first
MATRIX_TOKEN="your_actual_matrix_token"

# Test TEP token exchange
curl -X POST https://tmcp.example.com/api/v1/oauth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=urn:ietf:params:oauth:grant-type:token-exchange&subject_token=$MATRIX_TOKEN&client_id=tmcp-server&client_secret=YOUR_MAS_SECRET&scope=user:read"
```

### Test Mini-App Registration

```bash
curl -X POST https://tmcp.example.com/api/v1/mini-apps/register \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test Mini-App",
    "short_name": "TestApp",
    "description": "Test mini-app for deployment verification",
    "category": "utilities",
    "developer": {
      "company_name": "Test Corp",
      "email": "test@example.com"
    },
    "technical": {
      "entry_url": "https://test.example.com",
      "redirect_uris": ["https://test.example.com/callback"],
      "webhook_url": "https://api.test.example.com/webhooks",
      "scopes_requested": ["user:read"]
    }
  }'
```

## Step 6: Monitoring and Maintenance

### Logs

```bash
# TMCP Server logs
journalctl -u tmcp -f

# Nginx logs
tail -f /var/log/nginx/tmcp.access.log
tail -f /var/log/nginx/tmcp.error.log
```

### Database Maintenance

```bash
# Backup database
pg_dump tmcp > tmcp_backup.sql

# Check database size
psql -d tmcp -c "SELECT pg_size_pretty(pg_database_size('tmcp'));"
```

### Certificate Renewal

```bash
# Renew SSL certificates (Let's Encrypt example)
certbot renew --nginx
systemctl reload nginx
```

## Troubleshooting

### Common Issues

1. **MAS Token Introspection Fails**
   - Check MAS client secret matches
   - Verify MAS URL is accessible
   - Check firewall rules

2. **Matrix AS Registration Fails**
   - Verify HS token is valid
   - Check Synapse app_service_config syntax
   - Restart Synapse after config changes

3. **Database Connection Issues**
   - Verify PostgreSQL credentials
   - Check network connectivity
   - Confirm database exists and is accessible

4. **SSL Certificate Issues**
   - Verify certificate paths in Nginx config
   - Check certificate validity
   - Restart Nginx after certificate updates

### Debugging Commands

```bash
# Check TMCP service status
systemctl status tmcp

# Check MAS service status
systemctl status mas

# Test Matrix AS endpoint
curl -H "Authorization: Bearer YOUR_HS_TOKEN" \
  https://tmcp.example.com/_matrix/app/v1/users/@alice:example.com

# Test MAS introspection
curl -X POST https://auth.tween.im/oauth2/introspect \
  -u tmcp-server:YOUR_SECRET \
  -d "token=YOUR_MATRIX_TOKEN"
```

## Security Considerations

1. **Network Security**
   - Use HTTPS for all external communications
   - Restrict database access to internal networks
   - Implement proper firewall rules

2. **Application Security**
   - Keep Ruby and Rails versions updated
   - Regularly update dependencies
   - Monitor for security vulnerabilities

3. **Data Protection**
   - Encrypt sensitive data at rest
   - Implement proper access controls
   - Regular security audits

## Resources

- [TMCP Protocol Specification](https://github.com/Tween-IM/TMCP-Proto)
- [Matrix Application Service API](https://spec.matrix.org/latest/application-service/)
- [MAS Documentation](https://element-hq.github.io/matrix-authentication-service/)
- [Spantalev Documentation](https://docs.spantalev.org/)

## Support

For issues with this deployment guide:
1. Check the troubleshooting section
2. Review logs for error messages
3. Verify all prerequisites are met
4. Test individual components before full deployment