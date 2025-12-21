# TMCP Authentication & Authorization System Design

## 1. Overview

The TMCP Authentication & Authorization System provides secure access control for the mini-app ecosystem, supporting standard OAuth 2.0 flows with PKCE, multi-factor authentication, and granular scope-based authorization.

## 2. System Architecture

```mermaid
graph TB
    Client[Mini-App Client] --> AG[API Gateway]
    AG --> Auth[Authentication Service]
    Auth --> OAuth[OAuth Server]
    Auth --> MFA[MFA Service]
    Auth --> UserDB[(User Database)]
    Auth --> TokenStore[(Token Store)]
    
    MFA --> DeviceReg[Device Registry]
    MFA --> Biometric[Biometric Service]
    MFA --> TOTP[TOTP Service]
    MFA --> PinDB[(PIN Database)]
    
    subgraph "OAuth Flow Components"
        OAuth --> ClientReg[Client Registry]
        OAuth --> ScopeMgr[Scope Manager]
    end
    
    subgraph "MFA Components"
        Biometric --> DeviceReg
        TOTP --> UserDB
    end
```

## 3. Authentication Flow

### 3.1 Standard OAuth 2.0 with PKCE

```mermaid
sequenceDiagram
    participant C as Client
    participant A as Auth Service
    participant O as OAuth Server
    participant U as User
    participant M as MFA Service
    
    C->>A: Initiate auth request with code_challenge
    A->>O: Create authorization request
    O->>U: Redirect to login page
    U->>O: Submit credentials
    O->>M: Check if MFA required
    alt MFA Required
        M->>U: Send MFA challenge
        U->>M: Submit MFA response
        M->>O: Verify MFA response
    end
    O->>C: Return authorization code
    C->>O: Exchange code for tokens with code_verifier
    O->>C: Return access token, refresh token, ID token
```

### 3.2 MFA Challenge Flow

```mermaid
stateDiagram-v2
    [*] --> NoMFA
    NoMFA --> MFARequired: Check MFA policy
    MFARequired --> TransactionPin: Select PIN method
    MFARequired --> Biometric: Select biometric method
    MFARequired --> TOTP: Select TOTP method
    
    TransactionPin --> PinValidation: Submit PIN
    Biometric --> BiometricValidation: Submit biometric
    TOTP --> TOTPValidation: Submit TOTP code
    
    PinValidation --> Authenticated: Valid PIN
    BiometricValidation --> Authenticated: Valid biometric
    TOTPValidation --> Authenticated: Valid TOTP
    
    PinValidation --> PinFailed: Invalid PIN
    BiometricValidation --> BiometricFailed: Invalid biometric
    TOTPValidation --> TOTPFailed: Invalid TOTP
    
    PinFailed --> MFARequired: Retry
    BiometricFailed --> MFARequired: Retry
    TOTPFailed --> MFARequired: Retry
    
    Authenticated --> [*]
```

## 4. Component Details

### 4.1 Authentication Service

**Responsibilities:**
- User credential validation
- Session management
- Token issuance and validation
- Authentication event logging

**Key APIs:**
```
POST /auth/login
POST /auth/logout
POST /auth/refresh
POST /auth/validate
GET /auth/session
```

### 4.2 OAuth Server

**Responsibilities:**
- OAuth 2.0 authorization flows
- PKCE implementation
- Client registration and management
- Scope validation and enforcement

**Key APIs:**
```
GET /oauth/authorize
POST /oauth/token
POST /oauth/revoke
GET /oauth/userinfo
```

**OAuth Flow Implementation:**
- Authorization Code Flow with PKCE for public clients (mini-apps)
- Client Credentials Flow for server-to-server communication
- Refresh Token Flow for token renewal

### 4.3 MFA Service

**Responsibilities:**
- MFA method management
- Challenge generation and validation
- Device registration for biometrics
- MFA policy enforcement

**Key APIs:**
```
POST /mfa/challenge
POST /mfa/verify
POST /mfa/register-device
GET /mfa/methods
PUT /mfa/preferences
```

**MFA Methods:**
1. **Transaction PIN**
   - 6-digit numeric PIN
   - Rate limiting to prevent brute force
   - Locked after failed attempts

2. **Biometric Authentication**
   - Device-bound biometric keys
   - Attestation verification
   - Fallback to other methods

3. **TOTP (Time-based One-Time Password)**
   - RFC 6238 compliant implementation
   - QR code setup for authenticator apps
   - Backup codes for recovery

## 5. Authorization Model

### 5.1 Scope System

**Basic Scopes (auto-approved):**
- `profile` - Access to user profile information
- `email` - Access to user email
- `storage:read` - Read access to app storage
- `storage:write` - Write access to app storage

**Privileged Scopes (require approval):**
- `payment:read` - Read payment history
- `payment:write` - Initiate payments
- `payment:mfa` - Bypass MFA for small amounts
- `device:register` - Register devices for biometrics
- `app:install` - Install other apps
- `app:manage` - Manage app lifecycle

**Official App Scopes:**
- `admin:users` - User management
- `admin:apps` - App store management
- `admin:system` - System administration

### 5.2 Scope Validation

```mermaid
graph LR
    Request[API Request] --> AG[API Gateway]
    AG --> TV[Token Validation]
    TV --> SV[Scope Validation]
    SV --> Check[Permission Check]
    Check --> Allow[Allow Access]
    Check --> Deny[Deny Access]
    
    subgraph "Validation Steps"
        TV --> TokenValid[Token Valid?]
        SV --> ScopeValid[Has Required Scope?]
        Check --> ResourceAccess[Resource Access?]
    end
```

## 6. Security Considerations

### 6.1 Token Security

**Access Tokens:**
- JWT format with short expiration (15-60 minutes)
- Include user ID, scopes, and issuer
- Signed with asymmetric keys

**Refresh Tokens:**
- Long-lived tokens (30 days)
- Stored securely with rotation
- Bound to client device

### 6.2 PKCE Implementation

**Code Challenge Generation:**
```
code_verifier = random_string(43-128 chars)
code_challenge = BASE64URL(SHA256(code_verifier))
```

**Flow:**
1. Client generates code_verifier and code_challenge
2. Client sends code_challenge in authorization request
3. Server stores code_challenge with authorization code
4. Client sends code_verifier in token request
5. Server verifies code_verifier matches stored code_challenge

### 6.3 MFA Security

**Biometric Security:**
- Device-bound keys using platform secure storage
- Attestation verification to ensure device integrity
- Fallback mechanisms for device loss

**Transaction PIN Security:**
- Salted hash storage
- Rate limiting with exponential backoff
- Account lockout after repeated failures

**TOTP Security:**
- Time-based codes with 30-second window
- Backup codes for recovery scenarios
- Secure setup process with verification

## 7. Implementation Guidelines

### 7.1 Keycloak Integration (as mentioned in PROTO.md)

**Realm Configuration:**
- Dedicated TMCP realm
- Custom MFA flow providers
- Scope-based access policies
- Client registration for mini-apps

**Client Registration:**
- Dynamic client registration for mini-apps
- Pre-registered official apps with privileged scopes
- Client authentication methods (public vs confidential)

### 7.2 Database Schema

**Users Table:**
```sql
CREATE TABLE users (
    id UUID PRIMARY KEY,
    username VARCHAR(255) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    mfa_enabled BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

**MFA Methods Table:**
```sql
CREATE TABLE mfa_methods (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    method_type VARCHAR(50) NOT NULL, -- 'pin', 'biometric', 'totp'
    method_data JSONB NOT NULL,
    is_primary BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW()
);
```

**Device Registrations Table:**
```sql
CREATE TABLE device_registrations (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    device_id VARCHAR(255) NOT NULL,
    device_name VARCHAR(255),
    biometric_key_id VARCHAR(255),
    attestation_data JSONB,
    created_at TIMESTAMP DEFAULT NOW(),
    last_used TIMESTAMP
);
```

## 8. Rate Limiting

**Authentication Endpoints:**
- Login: 5 attempts per minute per IP
- MFA verification: 3 attempts per challenge
- Token refresh: 10 requests per minute per token

**Implementation:**
- Token bucket algorithm
- Sliding window counters
- Distributed storage for multi-instance deployments

## 9. Audit Logging

**Events to Log:**
- Successful and failed authentication attempts
- MFA challenges and responses
- Token issuance and refresh
- Scope usage and privilege escalations
- Device registrations and changes

**Log Format:**
```json
{
  "timestamp": "2025-12-20T01:15:00Z",
  "event_type": "auth.login.success",
  "user_id": "uuid",
  "client_id": "mini-app-id",
  "ip_address": "client-ip",
  "user_agent": "client-user-agent",
  "mfa_used": true,
  "scopes_granted": ["profile", "storage:read", "storage:write"]
}
```

This design provides a comprehensive authentication and authorization system that meets the TMCP protocol requirements while ensuring security, scalability, and maintainability.