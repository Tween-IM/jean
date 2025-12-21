# Tween Mini-App Communication Protocol (TMCP)

**TRFC:** 1001  
**Category:** Proposed Standard  
**Date:** December 2025  
**Authors:** Ezeani Emmanuel
**Handle:** @mona:tween.im

---

## Abstract

This document specifies the Tween Mini-App Communication Protocol (TMCP), a comprehensive protocol for secure communication between instant messaging applications and third-party mini-applications. Built as an isolated Application Service layer on the Matrix protocol, TMCP provides authentication, authorization, and wallet-based payment processing without modifying Matrix/Synapse core code. The protocol enables a super-app ecosystem with integrated wallet services, instant peer-to-peer transfers, mini-app payments, and social commerce within a closed federation environment.

---

## Status of This Memo

This document specifies a Proposed Standard protocol for the Internet community, and requests discussion and suggestions for improvements. Distribution of this memo is unlimited.

---

## Copyright Notice

Copyright (c) 2025 Tween IM. All rights reserved.

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Conventions and Terminology](#2-conventions-and-terminology)
3. [Protocol Architecture](#3-protocol-architecture)
4. [Identity and Authentication](#4-identity-and-authentication)
5. [Authorization Framework](#5-authorization-framework)
6. [Wallet Integration Layer](#6-wallet-integration-layer)
7. [Payment Protocol](#7-payment-protocol)
8. [Event System](#8-event-system)
9. [Mini-App Lifecycle](#9-mini-app-lifecycle)
10. [Communication Verbs](#10-communication-verbs)
11. [Security Considerations](#11-security-considerations)
12. [Error Handling](#12-error-handling)
13. [Federation Considerations](#13-federation-considerations)
14. [IANA Considerations](#14-iana-considerations)
15. [References](#15-references)
16. [Official and Preinstalled Mini-Apps](#16-official-and-preinstalled-mini-apps)
17. [Appendices](#17-appendices)

---

## 1. Introduction

### 1.1 Motivation

Modern instant messaging platforms increasingly serve as super-apps that integrate communication, commerce, and financial services. This specification defines a protocol that enables such functionality while maintaining protocol isolation from the underlying communication infrastructure.

The Tween Mini-App Communication Protocol (TMCP) addresses the following requirements:

- **Protocol Isolation**: Extensions to Matrix without core modifications
- **Wallet-Centric Architecture**: Integrated financial services as first-class citizens
- **Peer-to-Peer Transactions**: Direct value transfer between users within conversations
- **Mini-Application Ecosystem**: Third-party application integration with standardized APIs
- **Closed Federation**: Internal server infrastructure with centralized wallet management

### 1.2 Design Goals

**MUST Requirements:**
- Zero modification to Matrix/Synapse core protocol
- OAuth 2.0 + PKCE compliance for authentication
- Strong cryptographic signing for payment transactions
- Matrix Application Service API compatibility
- Real-time bidirectional communication
- Idempotent payment processing

**SHOULD Requirements:**
- Sub-200ms API response times for non-payment operations
- Sub-3s settlement time for peer-to-peer transfers
- Horizontal scalability across internal server instances
- Backwards compatibility for protocol updates

### 1.3 Scope

This specification defines:
- Mini-application registration and lifecycle management
- OAuth 2.0 authentication and authorization flows
- Wallet API for balance queries and peer-to-peer transfers
- Payment authorization protocol for mini-app transactions
- Event-driven communication patterns using Matrix events
- Security mechanisms for payment and data protection

This specification does NOT define:
- Wallet backend implementation details
- Matrix core protocol modifications
- Client user interface requirements
- External banking system integration specifics

---

## 2. Conventions and Terminology

### 2.1 Requirements Notation

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 [RFC2119].

### 2.2 Matrix Protocol Terms

**Homeserver**  
A Matrix server instance responsible for maintaining user state and federating events. In TMCP deployments, homeservers exist within a closed federation environment.

**User ID**  
Matrix user identifier in the format `@localpart:domain`. Example: `@alice:tween.example`

**Room**  
A persistent conversation context where events are shared between participants.

**Event**  
A JSON object representing an action, message, or state change in the Matrix ecosystem.

**Application Service (AS)**  
A server-side extension mechanism defined by the Matrix Application Service API that enables third-party services to integrate with a homeserver without modifying its core code.

### 2.3 TMCP-Specific Terms

**Mini-App (MA)**  
A third-party application running within the Tween client environment. Mini-Apps execute in sandboxed contexts and communicate with the host application via standardized APIs.

**Mini-App ID**  
Unique identifier for a registered mini-app, format: `ma_` followed by alphanumeric characters. Example: `ma_shop_001`

**TMCP Server**  
Application Service implementation that handles mini-app protocol operations including authentication, payment processing, and event routing.

**Tween Wallet**  
Integrated wallet service for storing digital currency balances and processing financial transactions.

**Wallet ID**  
User wallet identifier, format: `tw_` followed by alphanumeric characters. Example: `tw_user_12345`

**P2P Transfer**  
Peer-to-peer direct value transfer between user wallets within chat conversations.

**TEP Token (TMCP Extension Protocol Token)**  
JWT-based access token issued by the TMCP Server for mini-app authentication, distinct from Matrix access tokens.

---

## 3. Protocol Architecture

### 3.1 System Components

TMCP operates as an isolated layer that extends Matrix capabilities without modifying its core. The TMCP protocol defines interfaces between four independent systems:

1. **Element X/Classic Fork** (Client Application)
   - Matrix client implementation
   - TMCP Bridge component
   - Mini-app sandbox runtime

2. **Matrix Homeserver** (Synapse)
   - Standard Matrix protocol implementation
   - Application Service support

3. **TMCP Server** (Application Service)
   - Protocol coordinator
   - OAuth 2.0 authorization server
   - Mini-app registry

4. **Wallet Service** (Independent)
   - Balance management and ledger
   - Transaction processing
   - External gateway integration
   - **MUST implement TMCP-defined wallet interfaces**

This RFC defines the **protocol contracts** between these systems, not their internal implementations.

The architecture consists of these four primary components:

```
┌─────────────────────────────────────────────────────────┐
│                 TWEEN CLIENT APPLICATION                 │
│  ┌──────────────┐         ┌──────────────────────┐    │
│  │ Matrix SDK   │         │ TMCP Bridge          │    │
│  │ (Element)    │◄───────►│ (Mini-App Runtime)   │    │
│  └──────────────┘         └──────────────────────┘    │
└────────────┬──────────────────────┬───────────────────┘
             │                      │
             │ Matrix Client-       │ TMCP Protocol
             │ Server API           │ (JSON-RPC 2.0)
             │                      │
             ↓                      ↓
┌──────────────────┐     ┌──────────────────────────┐
│ Matrix Homeserver│◄───►│   TMCP Server            │
│ (Synapse)        │     │   (Application Service)  │
└──────────────────┘     └──────────────────────────┘
        │                          │
        │ Matrix                   ├──→ OAuth 2.0 Service
        │ Application              ├──→ Payment Processor
        │ Service API              ├──→ Mini-App Registry
        │                          └──→ Event Router
        │
        ↓
┌──────────────────┐     ┌──────────────────────────┐
│ Matrix Event     │     │   Tween Wallet Service   │
│ Store (DAG)      │     │   (gRPC/REST)            │
└──────────────────┘     └──────────────────────────┘
```

#### 3.1.1 Tween Client

The client application is a forked version of Element that implements the TMCP Bridge. Key responsibilities:

- **Matrix SDK Integration**: Standard Matrix client-server communication
- **TMCP Bridge**: WebView/iframe sandbox for mini-app execution
- **Hardware Security**: Leverages Secure Enclave (iOS) or TEE (Android) for payment signing
- **Event Rendering**: Custom rendering for TMCP-specific Matrix events

#### 3.1.2 TMCP Server (Application Service)

Server-side component that implements the Matrix Application Service API and provides TMCP-specific functionality:

**Registration with Homeserver:**
```yaml
# Application Service Configuration
id: tween-miniapps
url: https://tmcp.internal.example.com
as_token: <APPLICATION_SERVICE_TOKEN>
hs_token: <HOMESERVER_TOKEN>
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

**Functional Modules:**

1. **OAuth Service** - Issues TEP tokens, manages scopes
2. **Payment Processor** - Coordinates wallet transactions
3. **Mini-App Registry** - Stores application metadata
4. **Event Router** - Routes Matrix events to mini-apps
5. **Webhook Manager** - Dispatches notifications to mini-apps

#### 3.1.3 Matrix Homeserver

Standard Synapse homeserver with Application Service support. Responsibilities:

- Event persistence and ordering
- Room state management
- Federation (disabled in closed federation mode)
- Access control and authentication

#### 3.1.4 Tween Wallet Service

Separate service managing financial operations:

- Balance management
- Transaction ledger
- Payment settlement
- External gateway integration (bank APIs, payment processors)

### 3.2 Communication Patterns

#### 3.2.1 Client-to-Server Communication

**Matrix Protocol Path:**
```
Client → Matrix Client-Server API → Homeserver → Event Store
```

**TMCP Protocol Path:**
```
Client (Mini-App) → TMCP Bridge → TMCP Server → Wallet/Registry
```

#### 3.2.2 Event Flow for Payment Transaction

```
User initiates payment in Mini-App
     ↓
Mini-App calls TEP Bridge API
     ↓
Client displays payment confirmation UI
     ↓
User authorizes with biometric/PIN
     ↓
Client signs transaction with hardware key
     ↓
Signed transaction sent to TMCP Server
     ↓
TMCP Server validates signature
     ↓
TMCP Server coordinates with Wallet Service
     ↓
Wallet Service executes transfer
     ↓
TMCP Server creates Matrix event (m.tween.payment.completed)
     ↓
Homeserver persists event and distributes to room participants
     ↓
Client renders payment receipt
     ↓
Mini-App receives webhook notification
```

### 3.3 Protocol Layers

**Layer 1: Transport**
- HTTPS/TLS 1.3 (REQUIRED)
- WebSocket for real-time bidirectional communication
- Matrix federation protocol (closed federation only)

**Layer 2: Authentication**
- OAuth 2.0 with PKCE for mini-app authorization
- Matrix access tokens for client-server communication
- JWT (TEP tokens) for mini-app session management
- Hardware-backed signing for payments

**Layer 3: Application**
- JSON-RPC 2.0 for TMCP Bridge communication
- RESTful APIs for server-side operations
- Matrix custom events (m.tween.*) for state and messaging

**Layer 4: Security**
- End-to-end encryption (Matrix Olm/Megolm) for sensitive events
- HMAC-SHA256 for webhook signatures
- Request signing for payment authorization
- Content Security Policy for mini-app sandboxing

---

## 4. Identity and Authentication

### 4.1 Authentication Architecture

TMCP implements a dual-token system that separates Matrix identity from mini-app authorization:

1. **Matrix Access Token**: Used for Matrix client-server API calls
2. **TEP Token**: Used for mini-app-specific operations

This separation ensures mini-apps never access the user's primary Matrix credentials or encryption keys.

### 4.2 Mini-App Authentication Flow

#### 4.2.1 Authorization Code Flow with PKCE

TMCP implements OAuth 2.0 Authorization Code Flow with Proof Key for Code Exchange (PKCE) as defined in RFC 7636 [RFC7636].

**Step 1: Generate Code Verifier and Challenge**

The client MUST generate a code verifier and code challenge:

```javascript
// Generate code verifier (43-128 characters)
const codeVerifier = base64url(randomBytes(32));

// Generate code challenge
const codeChallenge = base64url(sha256(codeVerifier));
```

**Step 2: Authorization Request**

```http
GET /oauth2/authorize?
    response_type=code&
    client_id=ma_shop_001&
    redirect_uri=https://miniapp.example.com/callback&
    scope=user:read+wallet:pay&
    state=random_state_string&
    code_challenge=BASE64URL(SHA256(code_verifier))&
    code_challenge_method=S256
    
Host: tmcp.example.com
```

**Parameters:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| response_type | Yes | MUST be "code" |
| client_id | Yes | Mini-App ID |
| redirect_uri | Yes | HTTPS callback URL |
| scope | Yes | Space-separated scope list |
| state | Yes | CSRF protection token |
| code_challenge | Yes | Base64URL encoded SHA256 hash |
| code_challenge_method | Yes | MUST be "S256" |

**Step 3: User Consent**

The TMCP Server redirects to the client application, which displays a native consent screen showing:

```json
{
  "miniapp": {
    "id": "ma_shop_001",
    "name": "Shopping Assistant",
    "developer": "Example Corp",
    "icon_url": "https://cdn.example.com/icon.png",
    "verified": true
  },
  "requested_scopes": [
    {
      "scope": "user:read",
      "description": "Access your profile information",
      "sensitivity": "low"
    },
    {
      "scope": "wallet:pay",
      "description": "Process payments from your wallet",
      "sensitivity": "high",
      "note": "You'll confirm each payment"
    }
  ]
}
```

**Step 4: Authorization Response**

Upon user approval:

```http
HTTP/1.1 302 Found
Location: https://miniapp.example.com/callback?
    code=auth_abc123xyz&
    state=random_state_string
```

**Step 5: Token Request**

The mini-app backend exchanges the authorization code for tokens:

```http
POST /oauth2/token HTTP/1.1
Host: tmcp.example.com
Content-Type: application/x-www-form-urlencoded

grant_type=authorization_code&
code=auth_abc123xyz&
redirect_uri=https://miniapp.example.com/callback&
client_id=ma_shop_001&
client_secret=<CLIENT_SECRET>&
code_verifier=<CODE_VERIFIER>
```

**Step 6: Token Response**

```json
{
  "access_token": "tep.eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "refresh_token": "rt_abc123...",
  "scope": "user:read wallet:pay",
  "user_id": "@alice:tween.example",
  "wallet_id": "tw_user_12345"
}
```

### 4.3 TEP Token Structure

TEP tokens are JSON Web Tokens (JWT) as defined in RFC 7519 [RFC7519].

**Header:**
```json
{
  "alg": "RS256",
  "typ": "JWT",
  "kid": "tmcp-2024-12"
}
```

**Payload:**
```json
{
  "iss": "https://tmcp.example.com",
  "sub": "@alice:tween.example",
  "aud": "ma_shop_001",
  "exp": 1704067200,
  "iat": 1704063600,
  "jti": "unique-token-id",
  "scope": "user:read wallet:pay",
  "wallet_id": "tw_user_12345",
  "session_id": "session_xyz789",
  "miniapp_context": {
    "launch_source": "chat_bubble",
    "room_id": "!abc123:tween.example"
  }
}
```

**Claims:**

| Claim | Description |
|-------|-------------|
| iss | Issuer (TMCP Server URL) |
| sub | Subject (Matrix User ID) |
| aud | Audience (Mini-App ID) |
| exp | Expiration time (Unix timestamp) |
| iat | Issued at (Unix timestamp) |
| jti | JWT ID (unique identifier) |
| scope | Granted scopes |
| wallet_id | User's wallet identifier |
| session_id | Session identifier |
| miniapp_context | Launch context information |

### 4.4 Token Refresh

```http
POST /oauth2/token HTTP/1.1
Host: tmcp.example.com
Content-Type: application/x-www-form-urlencoded

grant_type=refresh_token&
refresh_token=rt_abc123...&
client_id=ma_shop_001&
client_secret=<CLIENT_SECRET>
```

Response:
```json
{
  "access_token": "tep.newtoken...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "refresh_token": "rt_newtoken...",
  "scope": "user:read wallet:pay"
}
```

**Token Rotation:**
- Refresh tokens MUST be single-use
- Old refresh token MUST be invalidated upon successful rotation
- Access token expiration: 1 hour (RECOMMENDED)
- Refresh token expiration: 30 days (RECOMMENDED)

### 4.5 Matrix Integration

TMCP creates virtual Matrix users for mini-app bots to send messages:

```http
POST /_matrix/client/v3/login HTTP/1.1
Authorization: Bearer <APP_SERVICE_TOKEN>
Content-Type: application/json

{
  "type": "m.login.application_service",
  "identifier": {
    "type": "m.id.user",
    "user": "@ma_shop_001_bot:tween.example"
  }
}
```

This allows mini-apps to:
- Send rich messages to rooms
- Participate in conversations as automated agents
- Create room state events for payment confirmations

---

## 5. Authorization Framework

### 5.1 Scope Definitions

Scopes define the permissions granted to mini-apps. Each scope MUST be explicitly requested during authorization and approved by the user.

**Scope Naming Convention:**
```
<category>:<action>[:<resource>]
```

**Standard Scopes:**

| Scope | Description | Sensitivity | User Approval Required |
|-------|-------------|-------------|------------------------|
| `user:read` | Read basic profile (name, avatar) | Low | Yes |
| `user:read:extended` | Read extended profile (status, bio) | Medium | Yes |
| `user:read:contacts` | Read friend list | High | Yes |
| `wallet:balance` | Read wallet balance | High | Yes |
| `wallet:pay` | Process payments | Critical | Yes (per transaction) |
| `wallet:history` | Read transaction history | High | Yes |
| `messaging:send` | Send messages to rooms | High | Yes |
| `messaging:read` | Read message history | High | Yes |
| `storage:read` | Read mini-app storage | Low | No |
| `storage:write` | Write to mini-app storage | Low | No |

### 5.2 Scope Validation

The TMCP Server MUST validate that all requested scopes are:
1. Syntactically valid
2. Registered for the requesting mini-app
3. Not escalated beyond initial registration

### 5.3 Permission Revocation

Users MAY revoke permissions at any time. When permissions are revoked:

1. TMCP Server MUST invalidate all TEP tokens for that mini-app/user pair
2. A Matrix state event MUST be created documenting the revocation:

```json
{
  "type": "m.room.tween.authorization",
  "state_key": "ma_shop_001",
  "content": {
    "authorized": false,
    "revoked_at": 1704067200,
    "revoked_scopes": ["wallet:pay"],
    "reason": "user_initiated"
  }
}
```

3. A webhook notification MUST be sent to the mini-app

---

## 6. Wallet Integration Layer

### 6.1 Wallet Architecture

The Tween Wallet Service operates independently from the TMCP Server and Matrix Homeserver:

```
TMCP Server ←→ gRPC/REST ←→ Wallet Service ←→ External Gateways
```

### 6.2 Wallet API Endpoints

#### 6.2.1 Get Balance

```http
GET /wallet/v1/balance HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
```

**Response:**
```json
{
  "wallet_id": "tw_user_12345",
  "user_id": "@alice:tween.example",
  "balance": {
    "available": 50000.00,
    "pending": 1500.00,
    "currency": "USD"
  },
  "limits": {
    "daily_limit": 100000.00,
    "daily_used": 25000.00,
    "transaction_limit": 50000.00
  },
  "verification": {
    "level": 2,
    "level_name": "ID Verified",
    "features": ["standard_transactions", "weekly_limit"],
    "can_upgrade": true,
    "next_level": 3,
    "upgrade_requirements": ["address_proof", "enhanced_id"]
  },
  "status": "active"
}
```


#### 6.2.2 Transaction History

```http
GET /wallet/v1/transactions?limit=50&offset=0 HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
```

**Response:**
```json
{
  "transactions": [
    {
      "txn_id": "txn_abc123",
      "type": "p2p_received",
      "amount": 5000.00,
      "currency": "USD",
      "from": {
        "user_id": "@bob:tween.example",
        "display_name": "Bob"
      },
      "status": "completed",
      "note": "Lunch money",
      "timestamp": "2025-12-18T12:00:00Z",
      "room_id": "!chat:tween.example"
    }
  ],
  "pagination": {
    "total": 245,
    "limit": 50,
    "offset": 0,
    "has_more": true
  }
}
J```

### 6.3 User Identity Resolution Protocol

#### 6.3.1 Overview

The TMCP protocol provides a standardized mechanism for resolving Matrix User IDs to Wallet IDs. This resolution is essential for:

1. **P2P Payments**: Sending money to chat participants
2. **Payment Requests**: Requesting money from specific users
3. **Transaction History**: Displaying sender/recipient information
4. **Profile Display**: Showing wallet status in user profiles

**Resolution Flow:**

```
Matrix Room → User clicks "Send Money" to @bob:tween.example
     ↓
Client → TMCP Server: Resolve Matrix ID to Wallet ID
     ↓
TMCP Server → Wallet Service: Get wallet for user
     ↓
Wallet Service → TMCP Server: Return wallet_id or error
     ↓
TMCP Server → Client: wallet_id or NO_WALLET error
     ↓
Client: Proceed with payment or show "User has no wallet"
```

#### 6.3.2 User Resolution Endpoint

**Resolve Single User:**

```http
GET /wallet/v1/resolve/@bob:tween.example HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
```

**Response (User has wallet):**
```json
{
  "user_id": "@bob:tween.example",
  "wallet_id": "tw_user_67890",
  "wallet_status": "active",
  "display_name": "Bob Smith",
  "avatar_url": "mxc://tween.example/avatar123",
  "payment_enabled": true,
  "created_at": "2024-01-15T10:00:00Z"
}
```

**Response (User has no wallet):**
```json
{
  "error": {
    "code": "NO_WALLET",
    "message": "User does not have a wallet",
    "user_id": "@bob:tween.example",
    "can_invite": true,
    "invite_message": "Invite Bob to create a Tween Wallet"
  }
}
```

**HTTP Status Codes:**
- 200 OK: User has active wallet
- 404 Not Found: User has no wallet (with NO_WALLET error body)
- 403 Forbidden: User has wallet but it's suspended/inactive
- 401 Unauthorized: Invalid TEP token

#### 6.3.3 Batch User Resolution

For efficiency when loading room member wallet statuses:

**Resolve Multiple Users:**

```http
POST /wallet/v1/resolve/batch HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
Content-Type: application/json

{
  "user_ids": [
    "@alice:tween.example",
    "@bob:tween.example",
    "@charlie:tween.example"
  ]
}
```

**Response:**

```json
{
  "results": [
    {
      "user_id": "@alice:tween.example",
      "wallet_id": "tw_user_12345",
      "wallet_status": "active",
      "payment_enabled": true
    },
    {
      "user_id": "@bob:tween.example",
      "wallet_id": "tw_user_67890",
      "wallet_status": "active",
      "payment_enabled": true
    },
    {
      "user_id": "@charlie:tween.example",
      "error": {
        "code": "NO_WALLET",
        "message": "User does not have a wallet"
      }
    }
  ],
  "resolved_count": 2,
  "total_count": 3
}
```

#### 6.3.4 Wallet Registration and Mapping

**Wallet Creation Flow:**

When a Matrix user creates a wallet, the mapping is established:

```http
POST /wallet/v1/register HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <MATRIX_ACCESS_TOKEN>
Content-Type: application/json

{
  "user_id": "@alice:tween.example",
  "currency": "USD",
  "initial_settings": {
    "mfa_enabled": false,
    "daily_limit": 100000.00
  }
}
```

**Response:**

```json
{
  "wallet_id": "tw_user_12345",
  "user_id": "@alice:tween.example",
  "status": "active",
  "balance": {
    "available": 0.00,
    "currency": "USD"
  },
  "created_at": "2025-12-18T14:30:00Z"
}
```

**Mapping Storage:**

The Wallet Service MUST maintain a bidirectional mapping:

| Matrix User ID | Wallet ID | Status | Created At |
|----------------|-----------|--------|------------|
| @alice:tween.example | tw_user_12345 | active | 2025-12-18T14:30:00Z |
| @bob:tween.example | tw_user_67890 | active | 2025-12-15T09:00:00Z |
| @mona:tween.im | tw_user_11111 | active | 2024-12-01T00:00:00Z |

**Wallet Service Interface Requirements:**

Wallet Service implementations MUST provide:

```
GetWalletByUserId(user_id: string) → wallet_id, status
GetWalletsByUserIds(user_ids: []string) → []WalletMapping
CreateWallet(user_id: string, settings: WalletSettings) → wallet_id
```

#### 6.3.5 P2P Payment with Matrix User ID

The P2P transfer endpoint (Section 7.2.1) accepts Matrix User IDs directly:

**Updated P2P Initiate Transfer:**

```http
POST /wallet/v1/p2p/initiate HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
Content-Type: application/json

{
  "recipient": "@bob:tween.example",
  "amount": 5000.00,
  "currency": "USD",
  "note": "Lunch money",
  "room_id": "!chat123:tween.example",
  "idempotency_key": "unique-uuid-here"
}
```

**TMCP Server Processing:**

1. Validate TEP token and extract sender's user_id and wallet_id
2. Resolve recipient Matrix ID to wallet_id:
   - Call Wallet Service: `GetWalletByUserId("@bob:tween.example")`
   - If no wallet found, return NO_WALLET error
   - If wallet suspended, return WALLET_SUSPENDED error
3. Validate room membership (both users must be in the specified room)
4. Proceed with payment authorization flow

**Error Response (No Wallet):**

```json
{
  "error": {
    "code": "RECIPIENT_NO_WALLET",
    "message": "Recipient does not have a wallet",
    "recipient": "@bob:tween.example",
    "can_invite": true,
    "invite_url": "tween://invite-wallet?user=@bob:tween.example"
  }
}
```

#### 6.3.6 Application Service Role in User Resolution

The TMCP Server (Application Service) acts as the resolution coordinator:

**Architecture:**

```
┌─────────────────────────────────────────────────────┐
│               TMCP Server (AS)                      │
│                                                     │
│  ┌──────────────────────────────────────────────┐ │
│  │      User Resolution Service                 │ │
│  │                                              │ │
│  │  • Maintains Matrix User ID → Wallet ID map │ │
│  │  • Caches resolution results (5 min TTL)    │ │
│  │  • Validates room membership                │ │
│  │  • Proxies to Wallet Service               │ │
│  └──────────────────────────────────────────────┘ │
└────────────────┬────────────────────────────────────┘
                 │
                 ↓
┌─────────────────────────────────────────────────────┐
│           Wallet Service                            │
│                                                     │
│  • Stores User ID ↔ Wallet ID mappings             │
│  • Enforces wallet status (active/suspended)       │
│  • Returns wallet metadata                         │
└─────────────────────────────────────────────────────┘
```

**AS Responsibilities:**

1. **Caching**: Cache user→wallet mappings to reduce Wallet Service load
   - Cache TTL: 5 minutes (RECOMMENDED)
   - Cache invalidation on wallet status changes
   - In-memory cache with Redis backup for multi-instance deployments

2. **Validation**: Verify room membership before exposing wallet information
   - User A can only resolve User B's wallet if they share a room
   - Prevents wallet enumeration attacks

3. **Rate Limiting**: Apply rate limits to resolution requests
   - 100 requests per minute per user (RECOMMENDED)
   - 1000 batch resolution requests per hour per user

#### 6.3.7 Room Context and Privacy

**Privacy Constraint:**

Users MAY only resolve wallet information for Matrix users they share a room with. This prevents enumeration attacks.

**Validation Flow:**

```
Client requests resolution of @bob:tween.example
     ↓
TMCP Server receives request with TEP token
     ↓
Extract requester: @alice:tween.example from token
     ↓
Query Matrix Homeserver: Do @alice and @bob share any room?
     ↓
If YES: Proceed with wallet resolution
If NO: Return 403 Forbidden
```

**Privacy-Preserving Resolution:**

```http
GET /wallet/v1/resolve/@bob:tween.example?room_id=!chat123:tween.example HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
```

The `room_id` parameter is OPTIONAL but RECOMMENDED for explicit room context validation.

#### 6.3.8 Client Implementation Example

**P2P Payment Button in Chat:**

```typescript
// Client-side implementation
class PaymentButton {
  async sendMoney(recipientUserId: string, roomId: string) {
    try {
      // Step 1: Resolve recipient's wallet
      const resolution = await tweenSDK.wallet.resolveUser(recipientUserId);
      
      if (!resolution.wallet_id) {
        // Show "Invite to Wallet" dialog
        this.showInviteDialog(recipientUserId);
        return;
      }
      
      // Step 2: Show payment dialog with recipient info
      const payment = await tweenSDK.wallet.requestPayment({
        recipient: recipientUserId,
        room_id: roomId,
        // UI will populate amount
      });
      
      // Step 3: Process payment
      await this.processPayment(payment);
      
    } catch (error) {
      if (error.code === 'RECIPIENT_NO_WALLET') {
        this.showInviteDialog(recipientUserId);
      } else if (error.code === 'WALLET_SUSPENDED') {
        this.showError('Recipient wallet is suspended');
      } else {
        this.showError(error.message);
      }
    }
  }
}
```

#### 6.3.9 Matrix Room Member Wallet Status

**Enhanced Room State Event:**

Clients MAY display wallet status indicators for room members:

```typescript
// Client queries all room members' wallet status
const members = await matrixClient.getRoomMembers(roomId);
const userIds = members.map(m => m.userId);

const walletStatuses = await tmcpServer.resolveUsersBatch(userIds);

// Display UI indicators:
// @alice:tween.example ✓ (has wallet)
// @bob:tween.example ✓ (has wallet)
// @charlie:tween.example ⚠ (no wallet - invite)
```

#### 6.3.10 Wallet Invitation Protocol

When a user attempts to send money to someone without a wallet:

**Invite Matrix Event:**

```json
{
  "type": "m.tween.wallet.invite",
  "content": {
    "msgtype": "m.tween.wallet_invite",
    "body": "Alice invited you to create a Tween Wallet",
    "inviter": "@alice:tween.example",
    "invitee": "@charlie:tween.example",
    "invite_url": "https://tween.example/wallet/create?inviter=alice",
    "incentive": {
      "type": "signup_bonus",
      "amount": 1000.00,
      "currency": "USD",
      "expires_at": "2025-12-25T00:00:00Z"
    }
  },
  "room_id": "!chat123:tween.example",
  "sender": "@alice:tween.example"
}
```

### 6.4 External Account Interface

#### 6.4.1 Overview

The TMCP protocol defines interfaces for external account operations, which are implemented by Wallet Service. These interfaces enable wallet funding and withdrawals through external financial accounts.

**Supported Account Types:**
- Bank accounts
- Debit/Credit cards
- Digital wallets
- Mobile money providers

#### 6.4.2 External Account Interface

The Wallet Service MUST implement these interfaces for external account operations:

```
LinkExternalAccount(user_id, account_details) → external_account_id
VerifyExternalAccount(account_id, verification_data) → status
FundWallet(user_id, source_account_id, amount) → funding_id
WithdrawToAccount(user_id, destination_account_id, amount) → withdrawal_id
```

#### 6.4.3 Protocol Response Format

All external account operations follow the standard response format defined in Section 12.1.

### 6.5 Withdrawal Interface

#### 6.5.1 Overview

The TMCP protocol defines interfaces for withdrawal operations, which are implemented by Wallet Service. These interfaces enable users to withdraw funds from their wallets.

#### 6.5.2 Withdrawal Interface

The Wallet Service MUST implement these interfaces for withdrawal operations:

```
InitiateWithdrawal(user_id, destination, amount) → withdrawal_id
ApproveWithdrawal(withdrawal_id, approval_data) → status
GetWithdrawalStatus(withdrawal_id) → withdrawal_details
```

#### 6.5.3 Protocol Response Format

All withdrawal operations follow the standard response format defined in Section 12.1.

---

## 7. Payment Protocol

### 7.1 Payment State Machine

Payments transition through well-defined states:

```
P2P Transfer States:
INITIATED → PENDING_RECIPIENT_ACCEPTANCE → COMPLETED
    ↓              ↓
CANCELLED    EXPIRED (24h)
    ↓              ↓
REJECTED ←─────────┘

Mini-App Payment States:
INITIATED → AUTHORIZED → PROCESSING → COMPLETED
              ↓              ↓
          EXPIRED        FAILED
              ↓              ↓
          CANCELLED ←───────┘
              ↓
          MFA_REQUIRED → (after MFA verification) → AUTHORIZED

Group Gift States:
CREATED → ACTIVE → PARTIALLY_OPENED → FULLY_OPENED
    ↓         ↓
EXPIRED   EXPIRED
```

### 7.2 Peer-to-Peer Transfer

#### 7.2.1 Initiate Transfer

```http
POST /wallet/v1/p2p/initiate HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
Content-Type: application/json

{
  "recipient": "@bob:tween.example",
  "amount": 5000.00,
  "currency": "USD",
  "note": "Lunch money",
  "idempotency_key": "unique-uuid-here"
}
```

**Idempotency Requirements:**
- Clients MUST include a unique idempotency key
- Servers MUST cache keys for 24 hours minimum
- Duplicate requests MUST return original response

**Response:**
```json
{
  "transfer_id": "p2p_abc123",
  "status": "completed",
  "amount": 5000.00,
  "sender": {
    "user_id": "@alice:tween.example",
    "wallet_id": "tw_user_12345"
  },
  "recipient": {
    "user_id": "@bob:tween.example",
    "wallet_id": "tw_user_67890"
  },
  "timestamp": "2025-12-18T14:30:00Z",
  "event_id": "$event_abc123:tween.example"
}
```

#### 7.2.2 Matrix Event for P2P Transfer

The TMCP Server MUST create a Matrix event documenting the transfer:

```json
{
  "type": "m.tween.wallet.p2p",
  "content": {
    "msgtype": "m.tween.money",
    "body": "💸 Sent $5,000.00",
    "transfer_id": "p2p_abc123",
    "amount": 5000.00,
    "currency": "USD",
    "note": "Lunch money",
    "sender": {
      "user_id": "@alice:tween.example"
    },
    "recipient": {
      "user_id": "@bob:tween.example"
    },
    "status": "completed",
    "timestamp": "2025-12-18T14:30:00Z"
  },
  "room_id": "!chat:tween.example",
  "sender": "@alice:tween.example"
}
```

#### 7.2.3 Recipient Acceptance Protocol

For enhanced security and user control, P2P transfers require explicit recipient acceptance before funds are released. This two-step confirmation pattern prevents accidental transfers and gives recipients control over incoming payments.

**Acceptance Flow:**

```
INITIATED → PENDING_RECIPIENT_ACCEPTANCE → COMPLETED
    ↓              ↓
CANCELLED    EXPIRED (24h)
    ↓              ↓
REJECTED ←─────────┘
```

**Acceptance Window:** 24 hours (RECOMMENDED)
**Auto-Expiry:** Transfers not accepted within window are auto-cancelled and refunded

**Accept Transfer:**

```http
POST /wallet/v1/p2p/{transfer_id}/accept HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <RECIPIENT_TEP_TOKEN>
Content-Type: application/json

{
  "device_id": "device_xyz789",
  "timestamp": "2025-12-18T14:32:00Z"
}
```

**Response:**
```json
{
  "transfer_id": "p2p_abc123",
  "status": "completed",
  "amount": 5000.00,
  "recipient": {
    "user_id": "@bob:tween.example",
    "wallet_id": "tw_user_67890"
  },
  "accepted_at": "2025-12-18T14:32:00Z",
  "new_balance": 12050.00
}
```

**Reject Transfer:**

```http
POST /wallet/v1/p2p/{transfer_id}/reject HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <RECIPIENT_TEP_TOKEN>
Content-Type: application/json

{
  "reason": "user_declined",
  "message": "Thanks but not needed"
}
```

**Response:**
```json
{
  "transfer_id": "p2p_abc123",
  "status": "rejected",
  "rejected_at": "2025-12-18T14:32:00Z",
  "refund_initiated": true,
  "refund_expected_at": "2025-12-18T14:32:30Z"
}
```

**Auto-Expiry Processing:**

TMCP Server MUST run scheduled jobs to process expired transfers:

```javascript
// TMCP Server scheduled job runs every hour
async function processExpiredTransfers() {
  const expired = await db.getTransfersByStatus('pending_recipient_acceptance')
    .where('created_at < NOW() - INTERVAL 24 HOURS');
  
  for (const transfer of expired) {
    // Refund to sender's wallet
    await walletService.refundTransfer(transfer.id);
    
    // Update Matrix event
    await matrixClient.sendEvent(transfer.room_id, {
      type: 'm.tween.wallet.p2p.status',
      content: {
        transfer_id: transfer.id,
        status: 'expired',
        expired_at: new Date().toISOString(),
        refunded: true
      }
    });
  }
}
```

**Updated Matrix Event for Pending Acceptance:**

```json
{
  "type": "m.tween.wallet.p2p",
  "content": {
    "msgtype": "m.tween.money",
    "body": "💸 Sent $5,000.00",
    "transfer_id": "p2p_abc123",
    "amount": 5000.00,
    "currency": "USD",
    "note": "Lunch money",
    "sender": {
      "user_id": "@alice:tween.example"
    },
    "recipient": {
      "user_id": "@bob:tween.example"
    },
    "status": "pending_recipient_acceptance",
    "expires_at": "2025-12-19T14:30:00Z",
    "actions": [
      {
        "type": "accept",
        "label": "Confirm Receipt",
        "endpoint": "/wallet/v1/p2p/p2p_abc123/accept"
      },
      {
        "type": "reject",
        "label": "Decline",
        "endpoint": "/wallet/v1/p2p/p2p_abc123/reject"
      }
    ],
    "timestamp": "2025-12-18T14:30:00Z"
  },
  "room_id": "!chat:tween.example",
  "sender": "@alice:tween.example"
}
```

**Status Update Event:**

```json
{
  "type": "m.tween.wallet.p2p.status",
  "content": {
    "transfer_id": "p2p_abc123",
    "status": "completed",
    "accepted_at": "2025-12-18T14:32:00Z",
    "visual": {
      "icon": "✓",
      "color": "green",
      "status_text": "Accepted"
    }
  }
}
```

### 7.3 Mini-App Payment Flow

#### 7.3.1 Payment Request

```http
POST /api/v1/payments/request HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
Content-Type: application/json

{
  "amount": 15000.00,
  "currency": "USD",
  "description": "Order #12345",
  "merchant_order_id": "ORDER-2024-12345",
  "items": [
    {
      "item_id": "prod_123",
      "name": "Product Name",
      "quantity": 2,
      "unit_price": 7500.00
    }
  ],
  "callback_url": "https://miniapp.example.com/webhooks/payment",
  "idempotency_key": "unique-uuid-here"
}
```

**Response:**
```json
{
  "payment_id": "pay_abc123",
  "status": "pending_authorization",
  "amount": 15000.00,
  "currency": "USD",
  "merchant": {
    "miniapp_id": "ma_shop_001",
    "name": "Shopping Assistant",
    "wallet_id": "tw_merchant_001"
  },
  "authorization_required": true,
  "expires_at": "2025-12-18T14:35:00Z",
  "created_at": "2025-12-18T14:30:00Z"
}
```

#### 7.3.2 Payment Authorization

The client displays a native payment confirmation UI. User authorizes using:
- Biometric authentication (fingerprint, face recognition)
- PIN code
- Hardware security module

**Authorization Signature:**

```javascript
// Client-side signing
const paymentHash = sha256(
  `${payment_id}:${amount}:${currency}:${timestamp}`
);

const signature = sign(paymentHash, hardwarePrivateKey);
```

**Submit Authorization:**

```http
POST /api/v1/payments/{payment_id}/authorize HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
Content-Type: application/json

{
  "signature": "base64_encoded_signature",
  "device_id": "device_xyz789",
  "timestamp": "2025-12-18T14:30:15Z"
}
```

#### 7.3.3 Payment Completion

**Response:**
```json
{
  "payment_id": "pay_abc123",
  "status": "completed",
  "txn_id": "txn_def456",
  "amount": 15000.00,
  "payer": {
    "user_id": "@alice:tween.example",
    "wallet_id": "tw_user_12345"
  },
  "merchant": {
    "miniapp_id": "ma_shop_001",
    "wallet_id": "tw_merchant_001"
  },
  "completed_at": "2025-12-18T14:30:20Z"
}
```

**Matrix Event:**

```json
{
  "type": "m.tween.payment.completed",
  "content": {
    "msgtype": "m.tween.payment",
    "body": "Payment of $15,000.00 completed",
    "payment_id": "pay_abc123",
    "txn_id": "txn_def456",
    "amount": 15000.00,
    "merchant": {
      "miniapp_id": "ma_shop_001",
      "name": "Shopping Assistant"
    },
    "status": "completed"
  }
}
```

### 7.4 Refunds

```http
POST /api/v1/payments/{payment_id}/refund HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
Content-Type: application/json

{
  "amount": 15000.00,
  "reason": "customer_request",
  "notes": "User requested refund"
}
```

### 7.5 Group Gift Distribution Protocol

#### 7.5.1 Overview

Group Gift Distribution provides a culturally relevant, gamified alternative to direct transfers. Inspired by traditional gifting practices, this feature enables social engagement through shared monetary gifts in chat contexts.

**Use Cases:**
- Gift giving for celebrations and special occasions
- Social engagement in group conversations
- Fun way to share money among multiple recipients
- Cultural celebrations and community building

#### 7.5.2 Create Group Gift

**Individual Gift:**

```http
POST /wallet/v1/gift/create HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
Content-Type: application/json

{
  "type": "individual",
  "recipient": "@bob:tween.example",
  "amount": 5000.00,
  "currency": "USD",
  "message": "Happy Birthday! 🎉",
  "room_id": "!chat123:tween.example",
  "idempotency_key": "unique-uuid"
}
```

**Group Gift:**

```http
POST /wallet/v1/gift/create HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
Content-Type: application/json

{
  "type": "group",
  "room_id": "!groupchat:tween.example",
  "total_amount": 10000.00,
  "currency": "USD",
  "count": 10,
  "distribution": "random",
  "message": "Happy Friday! 🎁",
  "expires_in_seconds": 86400,
  "idempotency_key": "unique-uuid"
}
```

**Response:**
```json
{
  "gift_id": "gift_abc123",
  "status": "active",
  "type": "group",
  "total_amount": 10000.00,
  "count": 10,
  "remaining": 10,
  "opened_by": [],
  "expires_at": "2025-12-19T14:30:00Z",
  "event_id": "$event_gift123:tween.example"
}
```

#### 7.5.3 Open Group Gift

```http
POST /wallet/v1/gift/{gift_id}/open HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
Content-Type: application/json

{
  "device_id": "device_xyz789"
}
```

**Response:**
```json
{
  "gift_id": "gift_abc123",
  "amount_received": 1250.00,
  "message": "Happy Friday! 🎁",
  "sender": {
    "user_id": "@alice:tween.example",
    "display_name": "Alice Smith"
  },
  "opened_at": "2025-12-18T14:30:15Z",
  "stats": {
    "total_opened": 3,
    "total_remaining": 7,
    "your_rank": 3
  }
}
```

#### 7.5.4 Group Gift Matrix Events

**Creation Event:**
```json
{
  "type": "m.tween.gift",
  "content": {
    "msgtype": "m.tween.gift",
    "body": "🎁 Gift: $100.00",
    "gift_id": "gift_abc123",
    "type": "group",
    "total_amount": 10000.00,
    "count": 10,
    "message": "Happy Friday! 🎁",
    "status": "active",
    "opened_count": 0,
    "actions": [
      {
        "type": "open",
        "label": "Open Gift",
        "endpoint": "/wallet/v1/gift/gift_abc123/open"
      }
    ]
  },
  "sender": "@alice:tween.example",
  "room_id": "!groupchat:tween.example"
}
```

**Update Event (each opening):**
```json
{
  "type": "m.tween.gift.opened",
  "content": {
    "gift_id": "gift_abc123",
    "opened_by": "@bob:tween.example",
    "amount": 1250.00,
    "opened_at": "2025-12-18T14:30:15Z",
    "remaining_count": 7,
    "leaderboard": [
      {"user": "@lisa:tween.example", "amount": 1500.00},
      {"user": "@sarah:tween.example", "amount": 1250.00},
      {"user": "@bob:tween.example", "amount": 1250.00}
    ]
  }
}
```

#### 7.5.5 Gift Distribution Algorithms

**Random Distribution:**
```javascript
function calculateRandomDistributions(totalAmount, count) {
  const distributions = [];
  let remaining = totalAmount;
  
  for (let i = 0; i < count - 1; i++) {
    // Ensure fair distribution: each amount is between 10% and 30% of average
    const minAmount = totalAmount * 0.1 / count;
    const maxAmount = remaining * 0.7; // Leave room for remaining recipients
    const amount = randomBetween(minAmount, maxAmount);
    
    distributions.push(Math.round(amount * 100) / 100); // Round to cents
    remaining -= amount;
  }
  
  // Last recipient gets remaining amount
  distributions.push(Math.round(remaining * 100) / 100);
  
  // Shuffle to randomize order
  return shuffleArray(distributions);
}
```

**Equal Distribution:**
```javascript
function calculateEqualDistributions(totalAmount, count) {
  const amount = Math.round((totalAmount / count) * 100) / 100;
  const distributions = Array(count).fill(amount);
  
  // Adjust for rounding errors
  const difference = totalAmount - (amount * count);
  if (difference !== 0) {
    distributions[0] += difference;
  }
  
  return distributions;
}
```

```http
POST /api/v1/payments/{payment_id}/refund HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
Content-Type: application/json

{
  "amount": 15000.00,
  "reason": "customer_request",
  "notes": "User requested refund"
}
```

### 7.4 Multi-Factor Authentication for Payments

#### 7.4.1 Overview

When Wallet Service implementations include multi-factor authentication requirements, the TMCP protocol provides a standardized challenge-response mechanism. The Wallet Service determines MFA policy; TMCP Server coordinates the challenge delivery and response validation.

**Protocol Flow:**

```
Client → TMCP Server: Payment Authorization
         ↓
TMCP Server → Wallet Service: Validate Payment
         ↓
Wallet Service → TMCP Server: MFA Required (if configured)
         ↓
TMCP Server → Client: MFA Challenge
         ↓
Client → User: Present MFA UI
         ↓
User → Client: Provide MFA Credentials
         ↓
Client → TMCP Server: MFA Response
         ↓
TMCP Server → Wallet Service: Validate MFA
         ↓
Wallet Service → TMCP Server: Validation Result
         ↓
TMCP Server → Client: Proceed or Retry
```

#### 7.4.2 MFA Challenge Request/Response

When a payment authorization is submitted and the Wallet Service requires additional authentication, the TMCP Server MUST return an MFA challenge:

**Challenge Response Format:**

```json
{
  "payment_id": "pay_abc123",
  "status": "mfa_required",
  "mfa_challenge": {
    "challenge_id": "mfa_ch_xyz789",
    "methods": [
      {
        "type": "transaction_pin",
        "enabled": true,
        "display_name": "Transaction PIN"
      },
      {
        "type": "biometric",
        "enabled": true,
        "display_name": "Biometric Authentication",
        "biometric_types": ["fingerprint", "face_recognition"]
      },
      {
        "type": "totp",
        "enabled": true,
        "display_name": "Authenticator Code"
      }
    ],
    "required_method": "any",
    "expires_at": "2025-12-18T14:32:15Z",
    "max_attempts": 3
  }
}
```

**Standard MFA Method Types:**

| Type | Description | Credential Format |
|------|-------------|-------------------|
| `transaction_pin` | Numeric PIN | `{"pin": "1234"}` |
| `biometric` | Device biometric verification | `{"attestation": "...", "biometric_type": "fingerprint"}` |
| `totp` | Time-based one-time password | `{"code": "123456"}` |

Wallet Service implementations MAY support additional method types through extension.

#### 7.4.3 MFA Response Submission

**Request Format:**

```http
POST /api/v1/payments/{payment_id}/mfa/verify HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
Content-Type: application/json

{
  "challenge_id": "mfa_ch_xyz789",
  "method": "transaction_pin",
  "credentials": {
    "pin": "1234"
  },
  "device_id": "device_xyz789",
  "timestamp": "2025-12-18T14:30:15Z"
}
```

**Success Response:**

```json
{
  "payment_id": "pay_abc123",
  "challenge_id": "mfa_ch_xyz789",
  "status": "verified",
  "proceed_to_processing": true
}
```

**Failure Response:**

```json
{
  "payment_id": "pay_abc123",
  "challenge_id": "mfa_ch_xyz789",
  "status": "failed",
  "error": {
    "code": "INVALID_CREDENTIALS",
    "message": "Invalid credentials provided",
    "attempts_remaining": 2
  },
  "retry_allowed": true
}
```

#### 7.4.4 Biometric Authentication Protocol

For biometric methods, clients MUST use platform-native biometric APIs and submit a cryptographic attestation rather than biometric data.

**Attestation Requirements:**

1. Client generates a signature over the payment challenge using a device-bound private key
2. Payload format: `{payment_id}:{challenge_id}:{timestamp}`
3. Signature algorithm: ECDSA P-256 or RSA-2048 minimum
4. Timestamp MUST be within 30 seconds of current time

**Example Request:**

```json
{
  "challenge_id": "mfa_ch_xyz789",
  "method": "biometric",
  "credentials": {
    "attestation": "MEUCIQDXz8fK...",
    "biometric_type": "fingerprint",
    "platform": "ios",
    "device_id": "device_xyz789",
    "timestamp": "2025-12-18T14:30:15Z"
  }
}
```

The TMCP Server forwards the attestation to the Wallet Service for verification. Wallet Service implementations MUST validate:
- Device is registered for the user
- Signature is valid for the registered public key
- Timestamp is recent

#### 7.4.5 Device Registration Protocol

Before biometric MFA can be used, devices MUST register their public keys.

**Registration Endpoint:**

```http
POST /wallet/v1/devices/register HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
Content-Type: application/json

{
  "device_id": "device_xyz789",
  "device_name": "Alice's iPhone 15",
  "platform": "ios",
  "public_key": {
    "algorithm": "ECDSA_P256",
    "format": "SPKI",
    "key_data": "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE..."
  },
  "biometric_capabilities": ["face_id", "touch_id"]
}
```

**Response:**

```json
{
  "device_id": "device_xyz789",
  "registered_at": "2025-12-18T14:30:00Z",
  "status": "active",
  "public_key_hash": "sha256:abcd1234..."
}
```

#### 7.4.6 Wallet Service MFA Interface Requirements

Wallet Service implementations that support MFA MUST implement the following gRPC interface (or REST equivalent):

**GetMFARequirements:**
- Input: wallet_id, payment_id, amount, currency
- Output: mfa_required (bool), available_methods, requirement_type, max_attempts

**VerifyMFAChallenge:**
- Input: wallet_id, challenge_id, method, credentials, device_id
- Output: verified (bool), attempts_remaining, locked (bool), locked_until

**RegisterDevice:**
- Input: wallet_id, device_id, public_key, biometric_capabilities
- Output: registration_status, public_key_hash

**ValidateBiometricAttestation:**
- Input: device_id, attestation, payload
- Output: valid (bool), error_reason

The TMCP Server acts as protocol coordinator but delegates all MFA policy and validation logic to the Wallet Service.

---

## 8. Event System

### 8.1 Custom Matrix Event Types

TMCP defines custom Matrix event types in the `m.tween.*` namespace.

#### 8.1.1 Mini-App Launch Event

```json
{
  "type": "m.tween.miniapp.launch",
  "content": {
    "miniapp_id": "ma_shop_001",
    "launch_source": "chat_bubble",
    "launch_params": {
      "product_id": "prod_123"
    },
    "session_id": "session_xyz789"
  },
  "sender": "@alice:tween.example"
}
```

#### 8.1.2 Payment Events

**Payment Request:**
```json
{
  "type": "m.tween.payment.request",
  "content": {
    "miniapp_id": "ma_shop_001",
    "payment": {
      "payment_id": "pay_abc123",
      "amount": 15000.00,
      "currency": "USD",
      "description": "Order #12345"
    }
  }
}
```

**Payment Completed:**
```json
{
  "type": "m.tween.payment.completed",
  "content": {
    "payment_id": "pay_abc123",
    "txn_id": "txn_def456",
    "status": "completed",
    "amount": 15000.00
  }
}
```

#### 8.1.3 Rich Message Cards

```json
{
  "type": "m.room.message",
  "content": {
    "msgtype": "m.tween.card",
    "miniapp_id": "ma_shop_001",
    "card": {
      "type": "product",
      "title": "Product Name",
      "description": "Product description",
      "image": "mxc://tween.example/image123",
      "price": {
        "amount": 7500.00,
        "currency": "USD"
      },
      "actions": [
        {
          "type": "button",
          "label": "Buy Now",
          "action": "miniapp.open",
          "params": {
            "miniapp_id": "ma_shop_001",
            "path": "/product/123"
          }
        }
      ]
    }
  }
}
```

### 8.2 Event Processing

#### 8.2.1 Application Service Transaction

The Matrix Homeserver sends events to the TMCP Server via the Application Service API:

```http
PUT /_matrix/app/v1/transactions/{txnId} HTTP/1.1
Authorization: Bearer <HS_TOKEN>
Content-Type: application/json

{
  "events": [
    {
      "type": "m.tween.payment.request",
      "content": {...},
      "sender": "@alice:tween.example",
      "room_id": "!chat:tween.example",
      "event_id": "$event_abc123:tween.example"
    }
  ]
}
```

**Response:**
```json
{
  "success": true
}
```

#### 8.1.4 App Lifecycle Events

**App Installation:**

```json
{
  "type": "m.tween.miniapp.installed",
  "content": {
    "miniapp_id": "ma_shop_001",
    "name": "Shopping Assistant",
    "version": "1.0.0",
    "classification": "verified",
    "installed_at": "2025-12-18T14:30:00Z"
  },
  "sender": "@alice:tween.example"
}
```

**App Update:**

```json
{
  "type": "m.tween.miniapp.updated",
  "content": {
    "miniapp_id": "ma_official_wallet",
    "previous_version": "2.0.0",
    "new_version": "2.1.0",
    "update_type": "minor",
    "updated_at": "2025-12-18T14:30:00Z"
  },
  "sender": "@_tmcp_updater:tween.example"
}
```

**App Uninstallation:**

```json
{
  "type": "m.tween.miniapp.uninstalled",
  "content": {
    "miniapp_id": "ma_shop_001",
    "uninstalled_at": "2025-12-18T14:30:00Z",
    "reason": "user_initiated",
    "data_cleanup": {
      "storage_cleared": true,
      "permissions_revoked": true
    }
  },
  "sender": "@alice:tween.example"
}
```

---

## 9. Mini-App Lifecycle

### 9.1 Registration

#### 9.1.1 Registration Request

```http
POST /mini-apps/v1/register HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <DEVELOPER_TOKEN>
Content-Type: application/json

{
  "name": "Shopping Assistant",
  "short_name": "ShopAssist",
  "description": "AI-powered shopping recommendations",
  "category": "shopping",
  "developer": {
    "company_name": "Example Corp",
    "email": "dev@example.com",
    "website": "https://example.com"
  },
  "technical": {
    "entry_url": "https://miniapp.example.com",
    "redirect_uris": [
      "https://miniapp.example.com/oauth/callback"
    ],
    "webhook_url": "https://api.example.com/webhooks/tween",
    "scopes_requested": [
      "user:read",
      "wallet:pay"
    ]
  },
  "branding": {
    "icon_url": "https://cdn.example.com/icon.png",
    "primary_color": "#FF6B00"
  }
}
```

**Response:**
```json
{
  "miniapp_id": "ma_shop_001",
  "status": "pending_review",
  "credentials": {
    "client_id": "ma_shop_001",
    "client_secret": "secret_abc123",
    "webhook_secret": "whsec_def456"
  },
  "created_at": "2025-12-18T14:30:00Z"
}
```

### 9.2 Lifecycle States

```
DRAFT → SUBMITTED → UNDER_REVIEW → APPROVED → ACTIVE
                         ↓
                    REJECTED
```

---

## 10. Communication Verbs

### 10.1 JSON-RPC 2.0 Bridge

Communication between mini-apps and the host application uses JSON-RPC 2.0 [RFC4627].

**Request Format:**
```json
{
  "jsonrpc": "2.0",
  "method": "tween.wallet.pay",
  "params": {
    "amount": 5000.00,
    "description": "Product purchase"
  },
  "id": 1
}
```

**Response Format:**
```json
{
  "jsonrpc": "2.0",
  "result": {
    "payment_id": "pay_abc123",
    "status": "completed"
  },
  "id": 1
}
```

### 10.2 Standard Methods

| Method | Direction | Description |
|--------|-----------|-------------|
| `tween.auth.getUserInfo` | MA → Host | Retrieve user profile |
| `tween.wallet.getBalance` | MA → Host | Get wallet balance |
| `tween.wallet.pay` | MA → Host | Initiate payment |
| `tween.wallet.sendGift` | MA → Host | Send group gift |
| `tween.wallet.openGift` | MA → Host | Open received gift |
| `tween.wallet.acceptTransfer` | MA → Host | Accept P2P transfer |
| `tween.wallet.rejectTransfer` | MA → Host | Reject P2P transfer |
| `tween.messaging.sendCard` | MA → Host | Send rich message card |
| `tween.storage.get` | MA → Host | Read storage |
| `tween.storage.set` | MA → Host | Write storage |
| `tween.lifecycle.onShow` | Host → MA | Mini-app shown |
| `tween.lifecycle.onHide` | Host → MA | Mini-app hidden |

### 10.3 Mini-App Storage System

#### 10.3.1 Overview

TMCP provides a key-value storage protocol for mini-apps to persist user-specific data. Storage is automatically namespaced per mini-app and per user, ensuring isolation.

**Storage Characteristics:**

- **Namespaced**: Keys automatically scoped to mini-app and user
- **Persistent**: Data survives app restarts
- **Quota-Limited**: Per-user, per-mini-app limits enforced
- **Eventually Consistent**: Offline operations supported
- **Encrypted**: Server-side encryption at rest REQUIRED

#### 10.3.2 Storage API Protocol

**Get Value:**

```http
GET /api/v1/storage/{key} HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
```

**Response:**
```json
{
  "key": "cart_items",
  "value": "{\"items\":[{\"id\":\"prod_123\",\"qty\":2}]}",
  "created_at": "2025-12-18T10:00:00Z",
  "updated_at": "2025-12-18T14:30:00Z",
  "metadata": {
    "size_bytes": 156,
    "content_type": "application/json"
  }
}
```

**Set Value:**

```http
PUT /api/v1/storage/{key} HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
Content-Type: application/json

{
  "value": "{\"items\":[{\"id\":\"prod_123\",\"qty\":2}]}",
  "ttl": 86400,
  "metadata": {
    "content_type": "application/json"
  }
}
```

**Delete Value:**

```http
DELETE /api/v1/storage/{key} HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
```

**List Keys:**

```http
GET /api/v1/storage?prefix=cart_&limit=100 HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
```

#### 10.3.3 Storage Quotas

**Protocol-Defined Limits:**

| Resource | Limit | Description |
|----------|-------|-------------|
| Total Storage | 10 MB | Per mini-app, per user |
| Maximum Key Length | 256 bytes | UTF-8 encoded |
| Maximum Value Size | 1 MB | Per key |
| Maximum Keys | 1000 | Per mini-app, per user |
| Operations Per Minute | 100 | Rate limit |

When quotas are exceeded:

```json
{
  "error": {
    "code": "STORAGE_QUOTA_EXCEEDED",
    "message": "Storage quota exceeded",
    "details": {
      "current_usage_bytes": 10485760,
      "quota_bytes": 10485760
    }
  }
}
```

#### 10.3.4 Time-To-Live (TTL)

Keys MAY specify a TTL in seconds. After expiration, keys MUST be automatically deleted.

**TTL Constraints:**
- Minimum: 60 seconds
- Maximum: 2592000 seconds (30 days)
- Default: No expiration (persistent)

#### 10.3.5 Offline Storage Protocol

Clients SHOULD implement offline caching to support disconnected operation. The protocol supports eventual consistency through client-side write queues.

**Offline Write Behavior:**

When offline, clients SHOULD:
1. Cache writes locally (e.g., IndexedDB)
2. Queue operations for synchronization
3. Sync when connectivity is restored

**Conflict Resolution:**

For concurrent modifications, protocol uses last-write-wins based on `client_timestamp`:

```http
PUT /api/v1/storage/{key} HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
Content-Type: application/json

{
  "value": "offline_written_value",
  "client_timestamp": 1703001234
}
```

If server value is newer, response indicates conflict:

```json
{
  "key": "cart_items",
  "success": true,
  "conflict_detected": true,
  "resolution": "server_wins",
  "server_value": "...",
  "updated_at": "2025-12-18T14:30:00Z"
}
```

#### 10.3.6 Batch Operations Protocol

For efficiency, protocol supports batch operations:

**Batch Get:**
```http
POST /api/v1/storage/batch/get HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
Content-Type: application/json

{
  "keys": ["cart_items", "user_preferences", "session_data"]
}
```

**Batch Set:**
```http
POST /api/v1/storage/batch/set HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
Content-Type: application/json

{
  "items": [
    {"key": "cart_items", "value": "{...}"},
    {"key": "user_preferences", "value": "{...}", "ttl": 86400}
  ]
}
```

#### 10.3.7 Storage Scopes

Storage operations require appropriate OAuth scopes:

| Scope | Operations |
|-------|------------|
| `storage:read` | GET, LIST |
| `storage:write` | PUT, DELETE, Batch operations |

These scopes are automatically granted to all mini-apps and do not require explicit user approval, as storage is already isolated per mini-app and per user.

#### 10.3.8 Storage Security Requirements

**Encryption:**
- All values MUST be encrypted at rest using AES-256 or stronger
- Encryption keys MUST be rotated periodically
- Per-user encryption keys RECOMMENDED

**Access Control:**
- Storage operations MUST validate TEP token
- Cross-user access MUST be prevented
- Cross-mini-app access MUST be prevented

**Data Lifecycle:**
- Storage MUST be deleted when user uninstalls mini-app
- Storage MUST be deleted when user account is deleted
- TTL expiration MUST be enforced

---

## 11. Security Considerations

### 11.1 Transport Security

- TLS 1.3 REQUIRED for all communications
- Certificate pinning RECOMMENDED for mobile clients
- HSTS with `max-age` >= 31536000 REQUIRED

### 11.2 Authentication Security

**Token Security:**
- Access tokens: 1 hour validity (RECOMMENDED)
- Refresh tokens: 30 days validity (RECOMMENDED)
- Tokens MUST be stored in secure storage (Keychain/KeyStore)
- Tokens MUST NOT be logged

**PKCE Requirements:**
- `code_challenge_method` MUST be `S256`
- Minimum `code_verifier` entropy: 256 bits

### 11.3 Payment Security

**Transaction Signing:**
- All payment authorizations MUST be signed
- Signatures MUST use hardware-backed keys when available
- Signature algorithm: ECDSA P-256 or RSA-2048 minimum

**Idempotency:**
- All payment requests MUST include idempotency keys
- Servers MUST cache idempotency keys for 24 hours minimum

### 11.4 Rate Limiting

Rate limits SHOULD be enforced using token bucket or sliding window algorithms.

**Required Rate Limit Headers:**

```http
HTTP/1.1 200 OK
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 87
X-RateLimit-Reset: 1704067260
```

When rate limit is exceeded:

```json
{
  "error": {
    "code": "RATE_LIMIT_EXCEEDED",
    "message": "Too many requests",
    "retry_after": 45
  }
}
```

**Status Code:** 429 Too Many Requests

| Operation | Limit | Window |
|-----------|-------|--------|
| Token generation | 10 | 1 minute |
| Payment requests | 20 | 1 minute |
| API calls | 100 | 1 minute |
| Webhook delivery | 1000 | 1 hour |

---

## 12. Error Handling

### 12.1 Error Response Format

```json
{
  "error": {
    "code": "INSUFFICIENT_FUNDS",
    "message": "Wallet balance too low",
    "details": {
      "required_amount": 15000.00,
      "available_balance": 8000.00
    },
    "timestamp": "2025-12-18T14:30:00Z",
    "request_id": "req_abc123"
  }
}
```

### 12.2 Standard Error Codes

| Code | HTTP Status | Description | Retry |
|------|-------------|-------------|-------|
| `INVALID_TOKEN` | 401 | Invalid or expired token | No |
| `INSUFFICIENT_PERMISSIONS` | 403 | Missing required scope | No |
| `INSUFFICIENT_FUNDS` | 402 | Low wallet balance | No |
| `PAYMENT_FAILED` | 400 | Payment processing error | Yes |
| `RATE_LIMIT_EXCEEDED` | 429 | Too many requests | Yes |
| `MINIAPP_NOT_FOUND` | 404 | Mini-app not registered | No |
| `INVALID_SIGNATURE` | 401 | Invalid payment signature | No |
| `DUPLICATE_TRANSACTION` | 409 | Idempotency key conflict | No |
| `MFA_REQUIRED` | 402 | Multi-factor authentication required | No |
| `MFA_LOCKED` | 429 | Too many failed MFA attempts | No |
| `INVALID_MFA_CREDENTIALS` | 401 | Invalid MFA credentials | Yes |
| `STORAGE_QUOTA_EXCEEDED` | 413 | Storage quota exceeded | No |
| `APP_NOT_REMOVABLE` | 403 | Official app cannot be removed | No |
| `APP_NOT_FOUND` | 404 | Mini-app not found | No |
| `DEVICE_NOT_REGISTERED` | 400 | Device not registered for MFA | No |
| `RECIPIENT_NO_WALLET` | 400 | Payment recipient has no wallet | No |
| `RECIPIENT_ACCEPTANCE_REQUIRED` | 400 | Recipient must accept payment | No |
| `TRANSFER_EXPIRED` | 400 | Transfer expired (24h window) | No |
| `GIFT_EXPIRED` | 400 | Group gift expired | No |

---

## 13. Federation Considerations

### 13.1 Closed Federation Model

TMCP deployments typically operate in closed federation mode:

- No external Matrix server federation
- All homeservers within controlled infrastructure
- Shared wallet backend
- Centralized TMCP Server instances

### 13.2 Multi-Server Deployment

For horizontal scaling, multiple instances can be deployed:

```
Load Balancer
     ↓
┌────────────────┐  ┌────────────────┐
│ TMCP Server 1  │  │ TMCP Server 2  │
└────────────────┘  └────────────────┘
         ↓                   ↓
    ┌────────────────────────────┐
    │  Shared Wallet Backend     │
    └────────────────────────────┘
```

Session affinity NOT required due to stateless design.

---

## 14. IANA Considerations

### 14.1 Matrix Event Type Registration

Request registration for the `m.tween.*` namespace:

- `m.tween.miniapp.*`
- `m.tween.wallet.*`
- `m.tween.payment.*`

### 14.2 OAuth Scope Registration

Request registration of TMCP-specific scopes:

- `user:read`
- `user:read:extended`
- `wallet:balance`
- `wallet:pay`
- `messaging:send`

---

## 15. References

### 15.1 Normative References

**[RFC2119]** Bradner, S., "Key words for use in RFCs to Indicate Requirement Levels", BCP 14, RFC 2119, March 1997.

**[RFC6749]** Hardt, D., "The OAuth 2.0 Authorization Framework", RFC 6749, October 2012.

**[RFC7636]** Sakimura, N., Bradley, J., and N. Agarwal, "Proof Key for Code Exchange by OAuth Public Clients", RFC 7636, September 2015.

**[RFC7519]** Jones, M., Bradley, J., and N. Sakimura, "JSON Web Token (JWT)", RFC 7519, May 2015.

**[RFC4627]** Crockford, D., "The application/json Media Type for JavaScript Object Notation (JSON)", RFC 4627, July 2006.

**[Matrix-Spec]** The Matrix.org Foundation, "Matrix Specification v1.12", https://spec.matrix.org/v1.12/

**[Matrix-AS]** The Matrix.org Foundation, "Matrix Application Service API", https://spec.matrix.org/v1.12/application-service-api/

### 15.2 Informative References

**[Matrix-CS]** The Matrix.org Foundation, "Matrix Client-Server API", https://spec.matrix.org/v1.12/client-server-api/

**[JSON-RPC]** "JSON-RPC 2.0 Specification", https://www.jsonrpc.org/specification

---

## 16. Official and Preinstalled Mini-Apps

### 16.1 Overview

The TMCP protocol distinguishes between third-party mini-apps and official applications. Official mini-apps MAY be preinstalled in the Element X/Classic fork and receive elevated permissions.

### 16.2 Mini-App Classification

**Classification Types:**

| Type | Description | Trust Model |
|------|-------------|-------------|
| `official` | Developed by Tween | Elevated permissions, preinstalled |
| `verified` | Vetted third-party | Standard permissions, verified developer |
| `community` | Unverified third-party | Standard permissions, caveat emptor |
| `beta` | Testing phase | Limited availability, opt-in |

Classification is assigned during registration and affects app capabilities and distribution.

### 16.3 Official Mini-App Registration

Official apps are registered with special attributes:

```http
POST /mini-apps/v1/register HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <ADMIN_TOKEN>
Content-Type: application/json

{
  "name": "Tween Wallet",
  "classification": "official",
  "developer": {
    "company_name": "Tween IM",
    "official": true
  },
  "preinstall": {
    "enabled": true,
    "platforms": ["ios", "android", "web", "desktop"],
    "install_mode": "mandatory"
  },
  "elevated_permissions": {
    "privileged_apis": [
      "system:notifications",
      "wallet:admin"
    ]
  }
}
```

**Install Modes:**

| Mode | Description | Removability |
|------|-------------|--------------|
| `mandatory` | Required system component | Cannot be removed |
| `default` | Preinstalled by default | Can be removed by user |
| `optional` | Available but not installed | User must explicitly install |

### 16.4 Preinstallation Manifest

Official mini-apps are defined in a manifest file embedded in the Element X/Classic fork client:

**Manifest Format (preinstalled_apps.json):**

```json
{
  "version": "1.0",
  "last_updated": "2025-12-18T00:00:00Z",
  "apps": [
    {
      "miniapp_id": "ma_official_wallet",
      "name": "Wallet",
      "category": "finance",
      "classification": "official",
      "install_mode": "mandatory",
      "removable": false,
      "icon": "builtin://icons/wallet.png",
      "entry_point": "tween-internal://wallet",
      "display_order": 1
    }
  ]
}
```

**Manifest Loading:**

On first launch, clients MUST:
1. Load embedded manifest
2. Register official apps with TMCP Server
3. Initialize app sandboxes
4. Mark bootstrap complete

### 16.5 Internal URL Scheme

Official apps MAY use the `tween-internal://` URL scheme for faster loading from embedded bundles.

**URL Format:**
```
tween-internal://{miniapp_id}[/{path}][?{query}]
```

**Examples:**
```
tween-internal://wallet
tween-internal://wallet/send?recipient=@bob:tween.example
```

Clients MUST resolve internal URLs to embedded app bundles rather than loading from network.

### 16.6 Mini-App Store Protocol

#### 16.6.1 App Discovery

**Get Categories:**

```http
GET /api/v1/store/categories HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
```

**Browse Apps:**

```http
GET /api/v1/store/apps?category=shopping&sort=popular&limit=20 HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
```

**Query Parameters:**

| Parameter | Values | Default |
|-----------|--------|---------|
| `category` | Category ID or "all" | "all" |
| `sort` | `popular`, `recent`, `rating`, `name` | "popular" |
| `classification` | `official`, `verified`, `community` | (all) |
| `limit` | 1-100 | 20 |
| `offset` | Integer | 0 |

**Response Format:**

```json
{
  "apps": [
    {
      "miniapp_id": "ma_shop_001",
      "name": "Shopping Assistant",
      "classification": "verified",
      "category": "shopping",
      "rating": {
        "average": 4.5,
        "count": 1250
      },
      "install_count": 50000,
      "icon_url": "https://cdn.tween.example/icons/shop.png",
      "version": "1.2.0",
      "preinstalled": false,
      "installed": false
    }
  ],
  "pagination": {
    "total": 145,
    "limit": 20,
    "offset": 0,
    "has_more": true
  }
}
```

#### 16.6.2 Installation Protocol

**Install Mini-App:**

```http
POST /api/v1/store/apps/{miniapp_id}/install HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
```

**Response:**

```json
{
  "miniapp_id": "ma_shop_001",
  "status": "installing",
  "install_id": "install_xyz789"
}
```

**Uninstall Mini-App:**

```http
DELETE /api/v1/store/apps/{miniapp_id}/install HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
```

Attempting to uninstall a `removable: false` official app MUST return:

```json
{
  "error": {
    "code": "APP_NOT_REMOVABLE",
    "message": "This system app cannot be removed"
  }
}
```

#### 16.6.3 App Ranking Protocol

Apps are ranked based on multiple factors:

**Ranking Factors:**

| Factor | Weight | Metric |
|--------|--------|--------|
| Install count | 30% | Total installations |
| Active users | 25% | 30-day active users |
| Rating | 20% | Average user rating |
| Engagement | 15% | Daily sessions per user |
| Recency | 10% | Recent updates |

**Trending Apps:**

Apps are "trending" when exhibiting:
- Install growth rate >20% week-over-week
- Rating improvements
- Increased engagement metrics

### 16.7 Official App Privileges

Official apps MAY access privileged scopes unavailable to third-party apps:

**Privileged Scopes:**

| Scope | Description | Official Only |
|-------|-------------|---------------|
| `system:notifications` | System-level notifications | Yes |
| `wallet:admin` | Wallet administration | Yes |
| `messaging:broadcast` | Broadcast messages | Yes |
| `analytics:detailed` | Detailed analytics | Yes |

### 16.8 Update Management Protocol

#### 16.8.1 Update Check

**Check for Updates:**

```http
POST /api/v1/client/check-updates HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
Content-Type: application/json

{
  "installed_apps": [
    {
      "miniapp_id": "ma_official_wallet",
      "current_version": "2.0.0"
    }
  ],
  "platform": "ios",
  "client_version": "2.1.0"
}
```

**Response:**

```json
{
  "updates_available": [
    {
      "miniapp_id": "ma_official_wallet",
      "current_version": "2.0.0",
      "new_version": "2.1.0",
      "update_type": "minor",
      "mandatory": false,
      "release_date": "2025-12-18T00:00:00Z",
      "release_notes": "Bug fixes and improvements",
      "download": {
        "url": "https://cdn.tween.example/bundles/wallet-2.1.0.bundle",
        "size_bytes": 3355443,
        "hash": "sha256:abcd1234...",
        "signature": "signature_xyz..."
      }
    }
  ]
}
```

**Update Verification Requirements:**

Clients MUST verify:
1. SHA-256 hash matches `download.hash`
2. Cryptographic signature is valid
3. Signature is from trusted Tween signing key

**Update Installation:**

Official apps with `install_mode: mandatory` MUST be updated automatically. Other apps MAY prompt user for approval.

#### 16.8.2 Client Bootstrap Protocol

On first launch, clients MUST perform bootstrap:

```http
POST /api/v1/client/bootstrap HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <MATRIX_ACCESS_TOKEN>
Content-Type: application/json

{
  "client_version": "2.1.0",
  "platform": "ios",
  "manifest_version": "1.0",
  "device_id": "device_xyz789"
}
```

**Response:**

```json
{
  "bootstrap_id": "bootstrap_abc123",
  "official_apps": [
    {
      "miniapp_id": "ma_official_wallet",
      "bundle_url": "https://cdn.tween.example/bundles/wallet-2.1.0.bundle",
      "bundle_hash": "sha256:abcd1234...",
      "credentials": {
        "client_id": "ma_official_wallet",
        "privileged_token": "token_abc123"
      }
    }
  ]
}
```

### 16.9 Official App Authentication

Official apps use the same OAuth 2.0 + PKCE flow as third-party apps but with pre-approved scopes to avoid user consent prompts for basic operations:

**Modified OAuth Flow for Official Apps:**

Official apps follow the standard PKCE flow defined in Section 4.2.1, but:
- Basic scopes (user:read, storage:read/write) are pre-approved
- Privileged scopes still require explicit user consent
- User consent UI indicates which scopes are pre-approved vs. requested

**Token Response for Official Apps:**

```json
{
  "access_token": "tep.eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "refresh_token": "rt_abc123...",
  "scope": "user:read storage:read storage:write",
  "user_id": "@alice:tween.example",
  "wallet_id": "tw_user_12345",
  "preapproved_scopes": ["user:read", "storage:read", "storage:write"],
  "privileged": false
}
```

**Privileged Token Response:**

For privileged operations, official apps receive tokens with additional claims:

```json
{
  "access_token": "tep.privileged_token...",
  "token_type": "Bearer",
  "expires_in": 86400,
  "scope": "user:read wallet:admin system:notifications",
  "user_id": "@alice:tween.example",
  "wallet_id": "tw_user_12345",
  "privileged": true,
  "privileged_until": 1704150400
}
```

**Security Requirements for Official Apps:**

Official apps MUST implement additional security measures:
- Code signing verification for all updates
- Audit logging for privileged operations
- Secure storage of privileged credentials
- Regular security reviews by Tween

### 16.10 OAuth Server Implementation with Keycloak

**Recommended Implementation: Keycloak Integration**

For production deployments, TMCP implementations are RECOMMENDED to use Keycloak as the OAuth 2.0 authorization server. Keycloak provides enterprise-grade identity and access management with the following advantages:

**Integration Architecture:**

```
┌─────────────────────────────────────────────────────────┐
│                 TWEEN CLIENT APPLICATION                 │
│  ┌──────────────┐         ┌──────────────────────┐    │
│  │ Matrix SDK   │         │ TMCP Bridge          │    │
│  │ (Element)    │◄───────►│ (Mini-App Runtime)   │    │
│  └──────────────┘         └──────────────────────┘    │
└────────────┬──────────────────────┬───────────────────┘
              │                      │
              │ Matrix Client-       │ TMCP Protocol
              │ Server API           │ (JSON-RPC 2.0)
              │                      │
              ↓                      ↓
┌──────────────────┐     ┌──────────────────────────┐
│ Matrix Homeserver│◄───►│   TMCP Server            │
│ (Synapse)        │     │   (Application Service)  │
└──────────────────┘     └──────────────────────────┘
         │                          │
         │ OAuth 2.0              ├──→ Keycloak Realm
         │ Authorization              │   (TMCP Apps)
         │                          ├──→ Client Registry
         │                          └──→ Token Validation
         │
         ↓
┌──────────────────────────────────────────────────┐
│            KEYCLOAK SERVER                │
│  ┌────────────────────────────────────┐   │
│  │ TMCP Realm Configuration      │   │
│  │ Client Registration           │   │
│  │ Token Service               │   │
│  │ MFA Service                │   │
│  └────────────────────────────────────┘   │
└──────────────────────────────────────────────────┘
```

**Keycloak Configuration for TMCP:**

**Realm Configuration:**
```json
{
  "realm": "tmcp",
  "displayName": "TMCP Mini-Apps",
  "enabled": true,
  "sslRequired": "external",
  "registrationAllowed": true,
  "loginWithEmailAllowed": false,
  "duplicateEmailsAllowed": false,
  "resetPasswordAllowed": false,
  "editUsernameAllowed": false,
  "bruteForceProtection": true,
  "maxFailureCount": 5,
  "failureResetTimeInSeconds": 900,
  "notBefore": 1704067200,
  "accessTokenLifespan": 3600,
  "ssoSessionMaxLifespan": 86400,
  "accessTokenLifespanRememberMe": 2592000,
  "refreshTokenLifespan": 2592000,
  "refreshTokenMaxReuse": 0,
  "otpPolicy": {
    "type": "totp",
    "digits": 6,
    "period": 30,
    "algorithm": "HmacSHA256"
  },
  "webAuthnPasswordPolicy": {
    "minLength": 8,
    "maxLength": 128,
    "hashAlgorithm": "pbkdf2-sha256"
  },
  "clientScopes": [
    "user:read",
    "user:read:extended",
    "user:read:contacts",
    "wallet:balance",
    "wallet:pay",
    "wallet:history",
    "messaging:send",
    "messaging:read",
    "storage:read",
    "storage:write"
  ],
  "officialAppScopes": [
    "system:notifications",
    "wallet:admin",
    "messaging:broadcast",
    "analytics:detailed"
  ]
}
```

**Client Registration:**
Each mini-app is registered as a Keycloak client with:
- Client ID matching mini-app ID
- Standard OAuth 2.0 flow with PKCE
- Redirect URIs configured for each mini-app
- Access type: confidential
- Valid redirect URIs enforced
- Service accounts enabled for privileged operations

**Token Service Configuration:**
- JWT signing with TMCP realm keys
- Custom claims for mini-app context and classification
- Standard and privileged scope enforcement
- Token introspection endpoint for TMCP Server validation

**MFA Service Integration:**
- MFA policies enforced at Keycloak level
- Device registration and management
- Biometric attestation validation
- Integration with Wallet Service for MFA verification

**Benefits of Keycloak Integration:**

1. **Enterprise Security**: Advanced security features, brute force protection, MFA policies
2. **Centralized Management**: Single admin console for all OAuth clients and scopes
3. **Audit Capabilities**: Comprehensive audit logging for compliance
4. **Scalability**: Horizontal scaling with clustering support
5. **Protocol Compliance**: Full OAuth 2.0 and OpenID Connect compliance
6. **Extensibility**: Custom protocol mappers for TMCP-specific requirements
7. **Multi-tenancy**: Support for multiple TMCP deployments from single Keycloak instance

**Implementation Notes:**

- TMCP Server acts as a Resource Owner in OAuth 2.0 terms
- Keycloak handles Authorization Server responsibilities
- Token validation and introspection endpoints proxy to Keycloak
- Privileged scopes mapped to Keycloak client-level permissions
- MFA challenges proxied through Keycloak's authentication flows

This integration maintains TMCP's security model while leveraging Keycloak's enterprise-grade identity management capabilities.

---

## 17. Appendices

### Appendix A: Complete Protocol Flow Example

**Scenario:** User purchases item from mini-app

1. User opens mini-app from chat
2. Mini-app requests `tween.auth.getUserInfo`
3. Client returns cached user info
4. User adds item to cart, clicks "Buy"
5. Mini-app calls `tween.wallet.pay`
6. Client displays payment confirmation UI
7. User authorizes with biometric
8. Client signs payment with hardware key
9. Client sends signed payment to TMCP Server
10. TMCP Server validates signature
11. TMCP Server coordinates with Wallet Service
12. Wallet Service executes transfer
13. TMCP Server creates Matrix event
14. Homeserver distributes event to room
15. Client renders payment receipt
16. TMCP Server sends webhook to mini-app
17. Mini-app processes order

### Appendix B: SDK Interface Definitions

**TypeScript Interface:**
```typescript
interface TweenSDK {
  auth: {
    getUserInfo(): Promise<UserInfo>;
    requestPermissions(scopes: string[]): Promise<boolean>;
  };
  
  wallet: {
    getBalance(): Promise<WalletBalance>;
    requestPayment(params: PaymentRequest): Promise<PaymentResult>;
  };
  
  messaging: {
    sendCard(params: CardParams): Promise<EventId>;
  };
  
  storage: {
    get(key: string): Promise<string | null>;
    set(key: string, value: string): Promise<void>;
  };
}
```

### Appendix C: Webhook Signature Verification

**Python Example:**
```python
import hmac
import hashlib

def verify_webhook(payload, signature, secret):
    expected = hmac.new(
        secret.encode(),
        payload.encode(),
        hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(f"sha256={expected}", signature)
```

---

**End of TRFC 1001**