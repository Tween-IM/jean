# Keycloak Integration for TMCP Server

This document provides instructions for integrating Keycloak as the OAuth 2.0 + OpenID Connect provider for the TMCP Server, as specified in TMCP Protocol Section 16.10.

## Overview

The TMCP Server now uses Keycloak for OAuth 2.0 authentication with PKCE support, replacing the previous mock implementation. This provides enterprise-grade security and compliance with the TMCP protocol requirements.

## Prerequisites

1. **Keycloak Server**: Running instance of Keycloak (v21+ recommended)
2. **TMCP Server**: Ruby on Rails application with the updated code
3. **Database**: PostgreSQL database configured
4. **Redis**: For caching and rate limiting

## Setup Instructions

### 1. Install Required Gems

Add the following gems to your Gemfile:

```ruby
gem "omniauth-keycloak"
```

Then run `bundle install`.

### 2. Configure Keycloak

#### Create Keycloak Realm
1. Log in to your Keycloak admin console
2. Create a new realm named "tween" (or update the existing one)
3. Configure the realm settings:
   - Enable PKCE
   - Set token lifespan (access token: 1 hour, refresh token: 30 days)
   - Enable email and profile scopes

#### Create Client
1. In the "Clients" section, create a new client:
   - Client ID: `tmcp-server`
   - Client Protocol: `openid-connect`
   - Access Type: `confidential`
   - Valid Redirect URIs: `https://tmcp.tween.im/api/v1/oauth2/callback`
   - Enable PKCE: `On`
   - Standard Flow Enabled: `On`
   - Direct Access Grants Enabled: `Off`

#### Configure Client Scopes
1. Go to "Client Scopes" and ensure the following are available:
   - `openid`
   - `email`
   - `profile`
   - TMCP-specific scopes (user:read, wallet:pay, etc.)

### 3. Environment Configuration

Copy the `.env.example` file to `.env` and update the values:

```bash
cp .env.example .env
```

Update the following variables:

```env
# Keycloak Configuration
KEYCLOAK_URL=https://iam.tween.im
KEYCLOAK_REALM=tween
KEYCLOAK_CLIENT_ID=tmcp-server
KEYCLOAK_CLIENT_SECRET=your_client_secret_here

# TMCP Server Configuration
TMCP_REDIRECT_URI=https://tmcp.tween.im/api/v1/oauth2/callback
```

### 4. Database Setup

Ensure your PostgreSQL database is properly configured and run the migrations:

```bash
rails db:create
rails db:migrate
```

### 5. Start the Server

Start the Rails server:

```bash
rails server
```

## Authentication Flow

The Keycloak integration implements the following OAuth 2.0 + PKCE flow:

1. **Authorization Request**: Mini-app redirects user to Keycloak
2. **User Consent**: User authenticates and consents to requested scopes
3. **Callback**: Keycloak redirects back to TMCP Server with authorization code
4. **Token Exchange**: TMCP Server exchanges code for access/refresh tokens
5. **TEP Token Generation**: TMCP Server generates TEP token for mini-app

## Security Features

- **PKCE Enforcement**: S256 code challenge method required
- **Token Validation**: JWT validation with proper claims verification
- **Scope Management**: TMCP-specific scopes properly enforced
- **State Parameter**: CSRF protection with state parameter
- **Token Rotation**: Refresh token rotation for enhanced security

## Testing

Run the test suite to verify the integration:

```bash
rails test
```

## Troubleshooting

### Common Issues

1. **Authentication Failures**
   - Verify Keycloak URL and credentials
   - Check redirect URI configuration
   - Ensure PKCE is enabled in Keycloak

2. **Token Exchange Errors**
   - Verify client secret
   - Check realm configuration
   - Ensure proper scope configuration

3. **Session Issues**
   - Verify Redis is running
   - Check session store configuration
   - Ensure proper cookie settings

## Compliance with TMCP Protocol

This implementation fully complies with TMCP Protocol Section 16.10 requirements:

- ✅ OAuth 2.0 + PKCE compliance
- ✅ Keycloak integration as recommended
- ✅ Enterprise-grade security features
- ✅ Centralized identity management
- ✅ Audit capabilities
- ✅ Scalability with clustering support
- ✅ Multi-tenancy support
- ✅ Custom protocol mappers for TMCP-specific requirements