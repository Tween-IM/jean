# Tween Mini-App Communication Protocol (TMCP)

**Document ID:** TMCP-001  
**Category:** Proposed Standard  
**Date:** December 2025  
**Authors:** Ezeani Emmanuel
**Handle:** @mona:tween.im

---

## Abstract

This document specifies the Tween Mini-App Communication Protocol (TMCP), a comprehensive protocol for secure communication between instant messaging applications and third-party mini-applications. Built as an isolated Application Service layer on the Matrix protocol, TMCP provides authentication, authorization, and wallet-based payment processing without modifying Matrix/Synapse core code. The protocol enables a super-app ecosystem with integrated wallet services, instant peer-to-peer transfers, mini-app payments, and social commerce. TMCP operates within Matrix's federation framework but assumes deployment in controlled federation environments for enhanced security.

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
    - [Appendix A: Complete Protocol Flow Example](#appendix-a-complete-protocol-flow-example)
    - [Appendix B: SDK Interface Definitions](#appendix-b-sdk-interface-definitions)
    - [Appendix C: WebView Implementation Details](#appendix-c-webview-implementation-details)
    - [Appendix D: Webhook Signature Verification](#appendix-d-webhook-signature-verification)

---

## 1. Introduction

### 1.1 Motivation

Modern instant messaging platforms increasingly serve as super-apps that integrate communication, commerce, and financial services. This specification defines a protocol that enables such functionality while maintaining protocol isolation from the underlying communication infrastructure.

The Tween Mini-App Communication Protocol (TMCP) addresses the following requirements:

- **Protocol Isolation**: Extensions to Matrix without core modifications
- **Wallet-Centric Architecture**: Integrated financial services as first-class citizens
- **Peer-to-Peer Transactions**: Direct value transfer between users within conversations
- **Mini-Application Ecosystem**: Third-party application integration with standardized APIs
- **Controlled Federation**: Internal server infrastructure with centralized wallet management

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
A Matrix server instance responsible for maintaining user state and federating events. In TMCP deployments, homeservers exist within a controlled federation environment.

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

Server-side component that implements the Matrix Application Service API and provides TMCP-specific functionality. The TMCP Server integrates with MAS for authentication while maintaining TMCP-specific authorization logic.

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

**TMCP Server Architecture:**

```
┌─────────────────────────────────────────────────────────────────────┐
│                      TMCP Server Components                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                    TMCP Server Core                           │  │
│  │                                                               │  │
│  │  ┌─────────────────────────────────────────────────────────┐ │  │
│  │  │              Authentication Middleware                   │ │  │
│  │  │                                                          │ │  │
│  │  │  - Validates TEP tokens (JWT)                           │ │  │
│  │  │  - Extracts user_id, wallet_id, scopes                  │ │  │
│  │  │  - Validates scope-based authorization                  │ │  │
│  │  │  - Gets MAS tokens for Matrix operations                │ │  │
│  │  └─────────────────────────────────────────────────────────┘ │  │
│  │                                                               │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                    Functional Modules                         │  │
│  │                                                               │  │
│  │  ┌─────────────────┐    ┌──────────────────────────────────┐ │  │
│  │  │ OAuth Service   │    │ MAS Client                       │ │  │
│  │  │                 │    │                                  │ │  │
│  │  │ - Issues TEP    │    │ - Client credentials grant       │ │  │
│  │  │ - Manages       │    │ - Token introspection           │ │  │
│  │  │   scopes       │    │ - Token refresh                  │ │  │
│  │  │ - TEP validation│    │ - Session management             │ │  │
│  │  └─────────────────┘    └──────────────────────────────────┘ │  │
│  │                                                               │  │
│  │  ┌─────────────────┐    ┌──────────────────────────────────┐ │  │
│  │  │ Payment         │    │ Mini-App Registry                │ │  │
│  │  │ Processor       │    │                                  │ │  │
│  │  │ - Validates     │    │ - Stores app metadata            │ │  │
│  │  │   wallet scopes │    │ - Manages client credentials     │ │  │
│  │  │ - Coordinates   │    │ - Tracks permissions             │ │  │
│  │  │   with Wallet   │    │ - Validates registration         │ │  │
│  │  └─────────────────┘    └──────────────────────────────────┘ │  │
│  │                                                               │  │
│  │  ┌─────────────────┐    ┌──────────────────────────────────┐ │  │
│  │  │ Event Router    │    │ Webhook Manager                  │ │  │
│  │  │                 │    │                                  │ │  │
│  │  │ - Routes Matrix │    │ - Dispatches notifications       │ │  │
│  │  │   events        │    │ - Handles callbacks              │ │  │
│  │  │ - Sends webhook │    │ - Manages delivery retry         │ │  │
│  │  │   payloads      │    │ - Validates signatures           │ │  │
│  │  └─────────────────┘    └──────────────────────────────────┘ │  │
│  │                                                               │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                    External Integrations                      │  │
│  │                                                               │  │
│  │  ┌─────────────────┐    ┌──────────────────────────────────┐ │  │
│  │  │ MAS Integration │    │ Wallet Service                   │ │  │
│  │  │                 │    │                                  │ │  │
│  │  │ - OAuth 2.0     │    │ - gRPC/REST interface            │ │  │
│  │  │ - Token mgmt    │    │ - Balance queries                │ │  │
│  │  │ - User session  │    │ - Transaction processing         │ │  │
│  │  │ - Scope policy  │    │ - Payment authorization          │ │  │
│  │  └─────────────────┘    └──────────────────────────────────┘ │  │
│  │                                                               │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

**MAS Client Configuration:**

```python
class MASClientConfig:
    """Configuration for MAS client integration."""
    
    def __init__(self):
        self.token_url = "https://mas.tween.example/oauth2/token"
        self.introspection_url = "https://mas.tween.example/oauth2/introspect"
        self.revocation_url = "https://mas.tween.example/oauth2/revoke"
        self.client_id = "ma_tmcp_server"
        self.client_secret_file = "/run/secrets/mas_client_secret"
        self.default_scopes = [
            "urn:matrix:org.matrix.msc2967.client:api:*"
        ]
        
        # Token caching
        self.token_cache_ttl = 240  # 4 minutes (expire 1 min early)
        
        # Load client secret
        with open(self.client_secret_file) as f:
            self.client_secret = f.read().strip()
```

**TMCP Server Authentication Endpoint:**

```python
@app.post("/oauth2/token")
async def token_endpoint(request: TokenRequest):
    """
    OAuth 2.0 token endpoint for TEP token issuance.
    
    This endpoint is used by MAS to issue TEP tokens during the
    initial authentication flow.
    """
    # Validate client credentials
    client = await validate_client(request.client_id, request.client_secret)
    
    # Get user info from MAS
    mas_user_info = await get_mas_user_info(request.matrix_access_token)
    
    # Generate TEP token
    tep_claims = {
        "iss": "https://tmcp.tween.example",
        "sub": mas_user_info["user_id"],
        "aud": request.client_id,
        "exp": datetime.utcnow() + timedelta(hours=24),
        "iat": datetime.utcnow(),
        "nbf": datetime.utcnow(),
        "jti": generate_unique_id(),
        "token_type": "tep_access_token",
        "client_id": request.client_id,
        "azp": request.client_id,
        "scope": " ".join(request.scopes or get_default_scopes()),
        "wallet_id": await get_or_create_wallet(mas_user_info["user_id"]),
        "session_id": generate_session_id(),
        "user_context": {
            "display_name": mas_user_info.get("display_name"),
            "avatar_url": mas_user_info.get("avatar_url")
        },
        "miniapp_context": request.miniapp_context or {},
        "mas_session": {
            "active": True,
            "refresh_token_id": request.refresh_token_id
        }
    }
    
    tep_token = jwt.encode(tep_claims, TMCP_PRIVATE_KEY, algorithm="RS256")
    
    return {
        "access_token": f"tep.{tep_token}",
        "token_type": "Bearer",
        "expires_in": 86400,
        "refresh_token": f"rt_{generate_unique_id()}",
        "scope": " ".join(tep_claims["scope"].split()),
        "user_id": mas_user_info["user_id"],
        "wallet_id": tep_claims["wallet_id"]
    }
```

#### 3.1.3 Matrix Homeserver

Standard Synapse homeserver with Application Service support. Responsibilities:

- Event persistence and ordering
- Room state management
- Federation (controlled within trusted infrastructure)
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
- Matrix federation protocol (controlled federation)

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

TMCP implements a dual-token architecture that separates concerns between TMCP operations and Matrix operations while maintaining unified user identity:

1. **TEP Token (JWT)**: Long-lived token for TMCP-specific operations, contains custom claims (wallet_id, scopes, miniapp_context)
2. **MAS Access Token**: Short-lived opaque token for Matrix operations, stored in memory only, never persisted

This separation ensures:
- Mini-apps have rich authorization claims for TMCP operations
- Matrix operations use standard OAuth 2.0 tokens managed by MAS
- Security is maintained with memory-only storage for sensitive Matrix tokens
- Token refresh is handled transparently without complex client logic

### 4.2 Authentication Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         TMCP Authentication                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                         Client Side                            │  │
│  │                                                                │  │
│  │  ┌────────────────┐    ┌──────────────────────────────────┐   │  │
│  │  │ TEP Token      │    │ MAS Access Token                 │   │  │
│  │  │ (JWT)          │    │ (Opaque, memory-only)            │   │  │
│  │  │                │    │                                  │   │  │
│  │  │ Stored in:     │    │ Stored in:                       │   │  │
│  │  │ - Keychain     │    │ - JavaScript memory              │   │  │
│  │  │ - EncryptedSP  │    │ - Swift variables                │   │  │
│  │  │ - HTTP cookie │    │ - Kotlin variables               │   │  │
│  │  │                │    │                                  │   │  │
│  │  │ Lifetime:      │    │ Lifetime:                        │   │  │
│  │  │ hours/days     │    │ 5 minutes (auto-expires)         │   │  │
│  │  │                │    │                                  │   │  │
│  │  │ Claims:        │    │ Usage:                           │   │  │
│  │  │ - user_id      │    │ - Matrix C-S API calls           │   │  │
│  │  │ - wallet_id    │    │ - Room operations                │   │  │
│  │  │ - scopes       │    │ - Event sending                  │   │  │
│  │  │ - miniapp_ctx  │    │                                  │   │  │
│  │  └────────┬───────┘    └──────────────┬───────────────────┘   │  │
│  │           │                            │                        │  │
│  │           ▼                            ▼                        │  │
│  │  ┌──────────────────────────────────────────────┐              │  │
│  │  │         TMCP Server Middleware               │              │  │
│  │  │                                              │              │  │
│  │  │  1. Validate TEP for TMCP operations         │              │  │
│  │  │  2. Use TEP claims for authorization         │              │  │
│  │  │  3. Get MAS token for Matrix operations      │              │  │
│  │  │  4. Proxy requests with proper credentials   │              │  │
│  │  └──────────────────────────────────────────────┘              │  │
│  │                                                                │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                    MAS (Matrix Authentication Service)         │  │
│  │                                                                │  │
│  │  - Issues TEP tokens via OAuth 2.0 authorization              │  │
│  │  - Issues MAS tokens for Matrix API access                    │  │
│  │  - Manages user sessions and refresh tokens                   │  │
│  │  - Token introspection and validation                         │  │
│  │                                                                │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 4.3 Initial Authentication Flow

#### 4.3.1 Device Authorization Grant (Recommended for Mini-Apps)

The Device Authorization Grant ([RFC 8628](https://datatracker.ietf.org/doc/html/rfc8628)) is recommended for mini-apps as it separates user authentication from device constraints.

**Step 1: Request Device Authorization**

```http
POST /oauth2/device/authorization HTTP/1.1
Host: mas.tween.example
Content-Type: application/x-www-form-urlencoded

client_id=ma_shop_001
&scope=urn:matrix:org.matrix.msc2967.client:api:*
```

**Step 2: Receive Authorization Details**

```json
{
  "device_code": "GmRhmhcxhwAzkoEqiMEg_DnyEysNkuNhszIySk9eS",
  "user_code": "WDJB-MJHR",
  "verification_uri": "https://mas.tween.example/oauth2/device",
  "verification_uri_complete": "https://mas.tween.example/oauth2/device?user_code=WDJB-MJHR",
  "expires_in": 900,
  "interval": 5
}
```

**Step 3: Display User Code to User**

The client displays the `user_code` and `verification_uri` to the user:

```
┌─────────────────────────────────────┐
│     Sign in to Tween Mini-App       │
├─────────────────────────────────────┤
│                                     │
│  1. Open: mas.tween.example         │
│                                     │
│  2. Enter code: WDJB-MJHR           │
│                                     │
│  3. Complete sign-in                │
│                                     │
│  [Loading...]                       │
└─────────────────────────────────────┘
```

**Step 4: Poll for Token**

```http
POST /oauth2/token HTTP/1.1
Host: mas.tween.example
Content-Type: application/x-www-form-urlencoded

grant_type=urn:ietf:params:oauth:grant-type:device_code
&device_code=GmRhmhcxhwAzkoEqiMEg_DnyEysNkuNhszIySk9eS
&client_id=ma_shop_001
&client_secret=<CLIENT_SECRET>
```

**Step 5: Token Response**

```json
{
  "access_token": "opaque_mas_token_abc123",
  "token_type": "Bearer",
  "expires_in": 300,
  "refresh_token": "refresh_mas_token_xyz789",
  "scope": "urn:matrix:org.matrix.msc2967.client:api:*",
  "tep_token": "tep.eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user_id": "@alice:tween.example"
}
```

**Step 6: Client Token Storage**

```javascript
await secureStorage.set('tep_token', 'tep.eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...');
await secureStorage.set('mas_refresh_token', 'refresh_mas_token_xyz789');
await secureStorage.set('tep_expires_at', Date.now() + 86400000);

let masAccessToken = 'opaque_mas_token_abc123';
let masAccessTokenExpiry = Date.now() + 300000;
```

#### 4.3.2 Authorization Code Grant (For Web Mini-Apps)

For web-based mini-apps running in browser, use Authorization Code Flow with PKCE ([RFC 7636](https://datatracker.ietf.org/doc/html/rfc7636)).

**Step 1: Generate PKCE Parameters**

```javascript
function generateCodeVerifier() {
  const array = new Uint8Array(32);
  crypto.getRandomValues(array);
  return base64urlEncode(array);
}

function generateCodeChallenge(verifier) {
  return base64urlEncode(sha256(verifier));
}

const codeVerifier = generateCodeVerifier();
const codeChallenge = generateCodeChallenge(codeVerifier);
const state = generateRandomString(16);
```

**Step 2: Redirect to Authorization Endpoint**

```
GET /oauth2/authorize?
    response_type=code&
    client_id=ma_shop_001&
    redirect_uri=https://miniapp.example.com/callback&
    scope=openid urn:matrix:org.matrix.msc2967.client:api:*&
    code_challenge=BASE64URL(SHA256(code_verifier))&
    code_challenge_method=S256&
    state=random_state_string
```

**Step 3: Exchange Code for Token**

```http
POST /oauth2/token HTTP/1.1
Host: mas.tween.example
Content-Type: application/x-www-form-urlencoded

grant_type=authorization_code
&code=auth_code_from_redirect
&redirect_uri=https://miniapp.example.com/callback
&client_id=ma_shop_001
&client_secret=<CLIENT_SECRET>
&code_verifier=<CODE_VERIFIER>
```

**Step 4: Token Response (Same as Device Flow)**

### 4.4 TEP Token Structure

TEP tokens are JSON Web Tokens (JWT) as defined in RFC 7519 [RFC7519], issued by the TMCP Server (acting as OAuth 2.0 authorization server for TMCP-specific operations).

**Header:**
```json
{
  "alg": "RS256",
  "typ": "JWT",
  "kid": "tmcp-2025-12"
}
```

**Payload:**
```json
{
  "iss": "https://tmcp.tween.example",
  "sub": "@alice:tween.example",
  "aud": "ma_shop_001",
  "exp": 1735689600,
  "iat": 1735603200,
  "nbf": 1735603200,
  "jti": "unique-token-id-abc123",
  "token_type": "tep_access_token",
  "client_id": "ma_shop_001",
  "azp": "ma_shop_001",
  "scope": "user:read wallet:pay wallet:balance storage:write messaging:send",
  "wallet_id": "tw_alice_123",
  "session_id": "session_xyz789",
  "user_context": {
    "display_name": "Alice",
    "avatar_url": "mxc://tween.example/avatar123"
  },
  "miniapp_context": {
    "launch_source": "chat_bubble",
    "room_id": "!abc123:tween.example"
  },
  "mas_session": {
    "active": true,
    "refresh_token_id": "rt_abc123"
  }
}
```

**Claims Reference:**

| Claim | Required | Description |
|-------|----------|-------------|
| `iss` | Yes | Issuer (TMCP Server URL) |
| `sub` | Yes | Subject (Matrix User ID) |
| `aud` | Yes | Audience (Mini-App ID) |
| `exp` | Yes | Expiration time (Unix timestamp) |
| `iat` | Yes | Issued at (Unix timestamp) |
| `nbf` | Yes | Not Before (Unix timestamp) |
| `jti` | Yes | Unique token identifier |
| `token_type` | Yes | Must be `tep_access_token` |
| `client_id` | Yes | Mini-App client ID |
| `azp` | Yes | Authorized party (same as client_id) |
| `scope` | Yes | Space-separated granted scopes |
| `wallet_id` | Yes | User's wallet identifier |
| `session_id` | Yes | Session identifier |
| `user_context` | No | User display info for UI |
| `miniapp_context` | No | Launch context information |
| `mas_session` | No | Matrix session reference |

### 4.5 Client-Side Token Management

#### 4.5.1 Secure Storage Requirements

**iOS Applications:**

```swift
import Security

struct TokenStorage {
    static func storeTEP(_ token: String) throws {
        let data = token.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "tep_token",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw TokenStorageError.osStatus(status)
        }
    }
    
    static func getTEP() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "tep_token",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return token
    }
}
```

**Android Applications:**

```kotlin
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

class TokenStorage(context: Context) {
    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()
    
    private val sharedPreferences = EncryptedSharedPreferences.create(
        context,
        "tmcp_secure_prefs",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )
    
    fun storeTEP(token: String) {
        sharedPreferences.edit()
            .putString("tep_token", token)
            .apply()
    }
    
    fun getTEP(): String? {
        return sharedPreferences.getString("tep_token", null)
    }
    
    fun storeRefreshToken(token: String) {
        sharedPreferences.edit()
            .putString("mas_refresh_token", token)
            .apply()
    }
    
    fun getRefreshToken(): String? {
        return sharedPreferences.getString("mas_refresh_token", null)
    }
}
```

**Web Applications:**

```javascript
// TEP stored in localStorage
localStorage.setItem('tep_token', 'tep.eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...');

// Refresh token stored in HTTP-only cookie
Set-Cookie: mas_refresh_token=refresh_token_abc123;
  HttpOnly;
  Secure;
  SameSite=Strict;
  Path=/;
  Max-Age=2592000
```

#### 4.5.2 In-Memory MAS Token Management

```javascript
class MASAuthenticator {
    constructor(config) {
        this.tokenUrl = config.tokenUrl;
        this.clientId = config.clientId;
        this.clientSecret = config.clientSecret;
        this.accessToken = null;
        this.accessTokenExpiry = null;
        this.refreshToken = null;
    }
    
    initialize(tokens) {
        this.accessToken = tokens.access_token;
        this.accessTokenExpiry = Date.now() + (tokens.expires_in * 1000);
        this.refreshToken = tokens.refresh_token;
    }
    
    async getAccessToken() {
        if (this.isTokenExpired()) {
            await this.refresh();
        }
        return this.accessToken;
    }
    
    isTokenExpired() {
        return Date.now() >= (this.accessTokenExpiry - 30000);
    }
    
    async refresh() {
        const response = await fetch(this.tokenUrl, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded'
            },
            body: new URLSearchParams({
                grant_type: 'urn:ietf:params:oauth:grant-type:refresh_token',
                refresh_token: this.refreshToken,
                client_id: this.clientId,
                client_secret: this.clientSecret
            })
        });
        
        if (!response.ok) {
            throw new AuthenticationError('Token refresh failed');
        }
        
        const tokens = await response.json();
        this.initialize(tokens);
        
        return this.accessToken;
    }
    
    clearMemoryToken() {
        this.accessToken = null;
        this.accessTokenExpiry = null;
    }
}

const masAuth = new MASAuthenticator({
    tokenUrl: 'https://mas.tween.example/oauth2/token',
    clientId: 'ma_shop_001',
    clientSecret: '<CLIENT_SECRET>'
});

masAuth.initialize({
    access_token: 'opaque_mas_token',
    expires_in: 300,
    refresh_token: 'refresh_token_xyz'
});

async function sendMatrixMessage(roomId, message) {
    const accessToken = await masAuth.getAccessToken();
    
    return fetch(`https://matrix.tween.example/_matrix/client/v3/rooms/${roomId}/send/m.room.message`, {
        method: 'POST',
        headers: {
            'Authorization': `Bearer ${accessToken}`,
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({
            msgtype: 'm.text',
            body: message
        })
    });
}
```

#### 4.5.3 Token Lifecycle Management

**On Initialization:**

```javascript
async function initializeAuth() {
    const tepToken = await secureStorage.getTEP();
    
    if (!tepToken) {
        await startDeviceAuthorizationFlow();
        return;
    }
    
    const tepClaims = decodeTEP(tepToken);
    if (tepClaims.exp * 1000 < Date.now()) {
        await startDeviceAuthorizationFlow();
        return;
    }
    
    const refreshToken = await secureStorage.getRefreshToken();
    if (refreshToken) {
        masAuth.refreshToken = refreshToken;
        await masAuth.refresh();
    }
}
```

**On TEP Expiration:**

```javascript
async function handleTEPExpired() {
    // TEP expired, need full re-authentication
    // Cannot refresh TEP (it's intentionally short-lived for security)
    await startDeviceAuthorizationFlow();
}
```

**On Logout:**

```javascript
async function logout() {
    await fetch('https://mas.tween.example/oauth2/revoke', {
        method: 'POST',
        body: new URLSearchParams({
            token: await secureStorage.getRefreshToken(),
            client_id: 'ma_shop_001',
            client_secret: '<CLIENT_SECRET>'
        })
    });
    
    await secureStorage.delete('tep_token');
    await secureStorage.delete('mas_refresh_token');
    
    masAuth.clearMemoryToken();
}
```

### 4.6 TMCP Server Authentication Middleware

```python
import jwt
import httpx
from typing import Optional, Dict, Any

class TMCPAuthMiddleware:
    def __init__(self, config):
        self.jwt_public_key = config.jwt_public_key
        self.mas_token_url = config.mas_token_url
        self.mas_client_id = config.mas_client_id
        self.mas_client_secret = config.mas_client_secret
        self.http_client = httpx.AsyncClient()
    
    async def authenticate_request(self, request) -> Dict[str, Any]:
        auth_header = request.headers.get('Authorization', '')
        if not auth_header.startswith('Bearer tep.'):
            raise Unauthorized("Missing TEP token")
        
        tep_token = auth_header[7:]
        
        tep_claims = await self._validate_tep(tep_token)
        
        required_scope = self._get_required_scope(request)
        if required_scope and required_scope not in tep_claims.get('scope', ''):
            raise Forbidden(f"Missing required scope: {required_scope}")
        
        return {
            'user_id': tep_claims['sub'],
            'wallet_id': tep_claims.get('wallet_id'),
            'miniapp_id': tep_claims['client_id'],
            'scopes': tep_claims.get('scope', '').split(),
            'session_id': tep_claims.get('session_id'),
            'miniapp_context': tep_claims.get('miniapp_context', {}),
            'tep_claims': tep_claims
        }
    
    async def _validate_tep(self, token: str) -> Dict[str, Any]:
        try:
            claims = jwt.decode(
                token,
                self.jwt_public_key,
                algorithms=['RS256'],
                audience='tmcp-server',
                issuer='https://tmcp.tween.example',
                options={
                    'verify_exp': True,
                    'verify_nbf': True,
                    'verify_iat': True,
                    'verify_iss': True,
                    'verify_aud': True
                }
            )
            return claims
        except jwt.ExpiredSignatureError:
            raise Unauthorized("TEP token expired")
        except jwt.InvalidTokenError as e:
            raise Unauthorized(f"Invalid TEP token: {e}")
    
    async def get_matrix_token(self, refresh_token: str) -> str:
        """Get fresh Matrix access token using refresh token."""
        response = await self.http_client.post(
            self.mas_token_url,
            data={
                'grant_type': 'urn:ietf:params:oauth:grant-type:refresh_token',
                'refresh_token': refresh_token,
                'client_id': self.mas_client_id,
                'client_secret': self.mas_client_secret
            }
        )
        
        if response.status_code != 200:
            raise Unauthorized("Failed to refresh Matrix token")
        
        return response.json()['access_token']
    
    async def proxy_matrix_request(
        self,
        matrix_token: str,
        method: str,
        endpoint: str,
        **kwargs
    ) -> httpx.Response:
        """Proxy request to Matrix homeserver."""
        headers = kwargs.get('headers', {})
        headers['Authorization'] = f'Bearer {matrix_token}'
        
        return await self.http_client.request(
            method,
            f"https://matrix.tween.example{endpoint}",
            headers=headers,
            json=kwargs.get('json'),
            params=kwargs.get('params')
        )
```

### 4.7 MAS Integration Requirements

#### 4.7.1 MAS Client Registration

The TMCP Server must be registered as a client in MAS with client credentials grant:

```yaml
# MAS configuration (config.yaml)
clients:
  - client_id: ma_tmcp_server
    client_auth_method: client_secret_post
    client_secret_file: /run/secrets/mas_client_secret
    grant_types:
      - authorization_code
      - urn:ietf:params:oauth:grant-type:device_code
      - refresh_token
      - urn:ietf:params:oauth:grant-type:reverse_1
    scope:
      - openid
      - urn:matrix:org.matrix.msc2967.client:api:*
      - urn:synapse:admin:*
```

#### 4.7.2 Mini-App Client Registration

Each mini-app must be registered in MAS with appropriate scopes:

```yaml
clients:
  - client_id: ma_shop_001
    client_auth_method: client_secret_post
    client_secret_file: /run/secrets/ma_shop_001_secret
    redirect_uris:
      - https://shop.miniapp.example.com/callback
    grant_types:
      - authorization_code
      - urn:ietf:params:oauth:grant-type:device_code
      - refresh:
      - open_token
    scopeid
      - urn:matrix:org.matrix.msc2967.client:api:*
```

### 4.8 Token Refresh Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                       Token Refresh Sequence                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  TEP Token (JWT)           MAS Access Token (Opaque)                 │
│  ┌──────────────┐         ┌─────────────────────┐                   │
│  │ Lifetime:     │         │ Lifetime:           │                   │
│  │ 24 hours      │         │ 5 minutes           │                   │
│  │              │         │                     │                   │
│  │ Refresh:     │         │ Refresh:            │                   │
│  │ Full OAuth   │         │ OAuth refresh_token │                   │
│  │ flow         │         │                     │                   │
│  └──────┬───────┘         └──────────┬──────────┘                   │
│         │                             │                               │
│         ▼                             ▼                               │
│  ┌──────────────┐             ┌─────────────────────┐               │
│  │ Re-auth with │             │ Auto-refresh on     │               │
│  │ device code  │             │ 401 response        │               │
│  │ or auth code │             │                     │               │
│  └──────────────┘             └─────────────────────┘               │
│                                                                      │
│  Timeline:                                                           │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                                                                │ │
│  │  TEP (24h) ──────────────────────────────────────────────────  │ │
│  │      │                                                          │ │
│  │      │  MAS (5m) ───┬── MAS ───┬── MAS ───┬── MAS ───        │ │
│  │      │              │          │          │          │         │ │
│  │      ▼              ▼          ▼          ▼          ▼         │ │
│  │    Initial      Refresh     Refresh    Refresh    Refresh    │ │
│  │    Auth         (5min)      (5min)     (5min)     (5min)     │ │
│  │                                                                │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  Operations:                                                         │
│  - Every 5 min: MAS token auto-refreshed via refresh_token          │
│  - Every 24h: Full re-authentication required for new TEP           │
│  - On TEP expiry: User must complete device code flow again         │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 4.9 Security Considerations

**Token Storage Security:**

| Token | Storage Location | Protection Mechanism |
|-------|-----------------|---------------------|
| TEP JWT | Secure storage (Keychain/EncryptedSharedPrefs/localStorage) | Platform-specific encryption |
| MAS Access Token | Memory only (JavaScript variable, Swift/Kotlin variable) | Never persisted |
| MAS Refresh Token | Secure storage | Same as TEP |

**Security Properties:**

1. **TEP Token**: 
   - Signed with RS256 (asymmetric)
   - Contains all authorization claims
   - Long-lived but revocable server-side
   - Stored encrypted at rest

2. **MAS Access Token**:
   - Opaque string (no claims exposed)
   - Short-lived (5 minutes)
   - Never written to disk or storage
   - Automatically refreshed
   - Memory-only access prevents XSS extraction

3. **Refresh Tokens**:
   - Long-lived (30 days)
   - Same storage security as TEP
   - Rotated on each use

**Attack Mitigation:**

| Attack Vector | Mitigation |
|---------------|------------|
| XSS stealing tokens | MAS token never persisted, only in memory |
| Local storage theft | TEP encrypted via platform security (Keychain/EncryptedSharedPrefs) |
| Token replay | Short-lived MAS tokens, TEP validated server-side |
| Replay attacks | JWT `jti` claim for deduplication |
| Token confusion | Explicit `token_type` claim in TEP |

### 4.10 Matrix Integration

TMCP Server proxies Matrix operations using the user's MAS credentials:

```python
async def handle_matrix_operation(
    self,
    auth_context: Dict[str, Any],
    operation: str,
    endpoint: str,
    **kwargs
) -> Dict[str, Any]:
    """Handle Matrix operation proxy."""
    refresh_token_id = auth_context['tep_claims']['mas_session']['refresh_token_id']
    
    refresh_token = await self.token_store.get(refresh_token_id)
    
    matrix_token = await self.get_matrix_token(refresh_token)
    
    response = await self.proxy_matrix_request(
        matrix_token,
        method=kwargs.get('method', 'GET'),
        endpoint=endpoint,
        **kwargs
    )
    
    return response.json()
```

### 4.11 In-Chat Payment Architecture

TMCP implements in-chat payment notifications where payment events appear natively in Matrix rooms. This approach provides a seamless user experience where payments feel integrated with the conversation rather than external notifications.

#### 4.11.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                    In-Chat Payment Architecture                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────────────┐   │
│  │ Mini-App    │────▶│ TMCP Server │────▶│ Wallet Service      │   │
│  │             │     │             │     │ (Third Party)       │   │
│  └─────────────┘     │             │     └─────────────────────┘   │
│                      │             │                               │
│                      │ Payment     │                               │
│                      │ Confirmed   │                               │
│                      │             │                               │
│                      └──────┬──────┘                               │
│                             │                                      │
│                             ▼                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │              Payment Event Flow                              │   │
│  │                                                              │   │
│  │  1. Wallet Service sends payment callback to TMCP Server    │   │
│  │  2. TMCP Server creates m.tween.payment event               │   │
│  │  3. TMCP Server sends event as @_tmcp_payments:tween.example│   │
│  │  4. Matrix Homeserver persists and distributes event        │   │
│  │  5. Client renders as rich payment card in chat             │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

#### 4.11.2 Virtual Payment Bot User

TMCP Server registers a virtual payment bot user in the Matrix namespace `@_tmcp_payments:*`:

```yaml
# Application Service Registration
id: tween-miniapps
url: https://tmcp.tween.example
as_token: <AS_TOKEN>
hs_token: <HS_TOKEN>
sender_localpart: _tmcp_payments
namespaces:
  users:
    - exclusive: true
      regex: "@_tmcp_payments:tween\\.example"
```

**Payment Bot Characteristics:**

| Attribute | Value |
|-----------|-------|
| User ID | `@_tmcp_payments:tween.example` |
| Display Name | "Tween Payments" |
| Avatar | Payment icon (consistent across all payments) |
| Purpose | Send payment receipts and status updates to rooms |
| Permissions | Can send events to any room where payment occurs |

**Why Virtual Bot User:**
- Consistent sender identity for all payment notifications
- No user credentials needed (uses AS token)
- Clear distinction from user messages
- Follows industry patterns where payments appear from the payment system

#### 4.11.3 Payment Event Types

TMCP defines payment event types in the `m.tween.payment.*` namespace:

| Event Type | Purpose | Direction |
|------------|---------|-----------|
| `m.tween.payment.sent` | Payment sent notification | Sender → Room |
| `m.tween.payment.completed` | Payment received confirmation | Recipient → Room |
| `m.tween.payment.failed` | Payment failure notification | System → Room |
| `m.tween.payment.refunded` | Refund processed | System → Room |
| `m.tween.p2p.transfer` | P2P transfer notification | System → Room |

#### 4.11.4 Rich Payment Event Structure

Payment events use a structured content format for rich rendering:

```json
{
  "type": "m.tween.payment.completed",
  "sender": "@_tmcp_payments:tween.example",
  "room_id": "!chat123:tween.example",
  "content": {
    "msgtype": "m.tween.payment",
    "payment_type": "completed",
    "visual": {
      "card_type": "payment_receipt",
      "icon": "payment_completed",
      "background_color": "#4CAF50"
    },
    "transaction": {
      "txn_id": "txn_abc123",
      "amount": 5000.00,
      "currency": "USD"
    },
    "sender": {
      "user_id": "@alice:tween.example",
      "display_name": "Alice",
      "avatar_url": "mxc://tween.example/avatar123"
    },
    "recipient": {
      "user_id": "@bob:tween.example",
      "display_name": "Bob",
      "avatar_url": "mxc://tween.example/avatar456"
    },
    "note": "Lunch money",
    "timestamp": "2025-12-18T14:30:00Z",
    "actions": [
      {
        "type": "view_receipt",
        "label": "View Details",
        "endpoint": "/wallet/v1/transactions/txn_abc123"
      }
    ]
  }
}
```

#### 4.11.5 Client Rendering Requirements

Clients MUST render payment events as rich cards for in-chat payment notifications:

**Payment Receipt Card:**

```
┌─────────────────────────────────────┐
│ 💰 Payment Completed                │
├─────────────────────────────────────┤
│                                     │
│  From: Alice                        │
│  Amount: $5,000.00 USD              │
│                                     │
│  Note: Lunch money                  │
│                                     │
│  ────────────────────────────────   │
│  Transaction ID: txn_abc123         │
│  Dec 18, 2025 2:30 PM               │
│                                     │
│  [View Details]                     │
└─────────────────────────────────────┘
```

**P2P Transfer Card:**

```
┌─────────────────────────────────────┐
│ 💸 Transfer Sent                    │
├─────────────────────────────────────┤
│                                     │
│  To: Bob                            │
│  Amount: $5,000.00 USD              │
│                                     │
│  Note: Lunch money                  │
│                                     │
│  ────────────────────────────────   │
│  Status: Completed                  │
│  Transaction ID: p2p_abc123         │
│                                     │
│  [View Receipt]  [Send Again]       │
└─────────────────────────────────────┘
```

**Client Implementation:**

```typescript
interface PaymentEventRenderer {
    canRender(eventType: string): boolean;
    
    render(event: MatrixEvent): PaymentCardView;
    
    handleAction(action: string, event: MatrixEvent): void;
}

class PaymentEventHandler implements PaymentEventRenderer {
    canRender(eventType: string): boolean {
        return eventType.startsWith('m.tween.payment.');
    }
    
    render(event: MatrixEvent): PaymentCardView {
        const content = event.content;
        
        switch (content.payment_type) {
            case 'completed':
                return this.renderCompletedPayment(content);
            case 'sent':
                return this.renderSentPayment(content);
            case 'failed':
                return this.renderFailedPayment(content);
            default:
                return this.renderGenericPayment(content);
        }
    }
    
    private renderCompletedPayment(content: any): PaymentCardView {
        return {
            type: 'payment_receipt',
            title: '💰 Payment Completed',
            sections: [
                {
                    type: 'user_info',
                    user_id: content.sender.user_id,
                    display_name: content.sender.display_name,
                    avatar_url: content.sender.avatar_url
                },
                {
                    type: 'amount',
                    amount: content.transaction.amount,
                    currency: content.transaction.currency
                },
                {
                    type: 'note',
                    text: content.note
                },
                {
                    type: 'metadata',
                    items: [
                        { label: 'Transaction ID', value: content.transaction.txn_id },
                        { label: 'Time', value: content.timestamp }
                    ]
                }
            ],
            actions: content.actions
        };
    }
}
```

#### 4.11.6 Payment Event Flow Sequence

```
User A sends payment to User B in chat room
                  │
                  ▼
┌─────────────────────────────────────────┐
│ 1. Mini-app calls tween.wallet.pay      │
└───────────────────┬─────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ 2. Client displays payment confirmation │
│    User authorizes with biometric/PIN   │
└───────────────────┬─────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ 3. Client signs and sends to TMCP       │
└───────────────────┬─────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ 4. TMCP Server validates, forwards to   │
│    Wallet Service                       │
└───────────────────┬─────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ 5. Wallet Service processes payment     │
│    Sends callback to TMCP Server        │
└───────────────────┬─────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ 6. TMCP Server creates payment event    │
│    Sender: @_tmcp_payments:tween.example│
│    Room: !chat123:tween.example         │
│    Event: m.tween.payment.completed     │
└───────────────────┬─────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ 7. TMCP Server sends event using AS     │
│    Authorization: Bearer <AS_TOKEN>     │
│                                          │
│    POST /_matrix/client/v3/rooms/       │
│        !chat123:tween.example/send/     │
│        m.tween.payment.completed        │
└───────────────────┬─────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ 8. Matrix Homeserver persists event     │
│    Distributes to all room members      │
└───────────────────┬─────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ 9. Client receives and renders as       │
│    rich payment card in chat              │
└─────────────────────────────────────────┘
```

#### 4.11.7 Third-Party Wallet Integration

For third-party wallet providers, TMCP Server acts as the integration layer:

**Wallet Provider Requirements:**

1. **Payment Callback Endpoint:**
   ```http
   POST /api/v1/wallet/callback HTTP/1.1
   Host: tmcp.tween.example
   Content-Type: application/json
   
   {
     "event": "payment.completed",
     "transaction_id": "txn_wallet_123",
     "amount": 5000.00,
     "currency": "USD",
     "sender": {
       "user_id": "@alice:tween.example",
       "wallet_id": "tw_alice_123"
     },
     "recipient": {
       "user_id": "@bob:tween.example",
       "wallet_id": "tw_bob_456"
     },
     "room_id": "!chat123:tween.example",
     "note": "Lunch money",
     "timestamp": "2025-12-18T14:30:00Z",
     "signature": "base64_signature"
   }
   ```

2. **Signature Verification:**
   ```python
   async def verify_wallet_callback(
       self,
       payload: dict,
       signature: str,
       wallet_id: str
   ) -> bool:
       """Verify wallet provider callback signature."""
       wallet = await self.wallet_registry.get(wallet_id)
       
       return verify_signature(
           payload,
           signature,
           wallet.webhook_secret
       )
   ```

3. **Event Creation from Callback:**
   ```python
   async def create_payment_event(
       self,
       callback_data: dict
   ) -> str:
       """Create Matrix event from wallet callback."""
       event_content = {
           "msgtype": "m.tween.payment",
           "payment_type": self._map_event_type(callback_data['event']),
           "visual": self._get_payment_visual(callback_data),
           "transaction": {
               "txn_id": callback_data['transaction_id'],
               "amount": callback_data['amount'],
               "currency": callback_data['currency']
           },
           "sender": callback_data['sender'],
           "recipient": callback_data['recipient'],
           "note": callback_data.get('note', ''),
           "timestamp": callback_data['timestamp']
       }
       
       # Send event as payment bot
       response = await self.matrix_client.send_event(
           access_token=self.as_token,
           room_id=callback_data['room_id'],
           event_type="m.tween.payment.completed",
           event_content=event_content
       )
       
       return response['event_id']
   ```

#### 4.11.8 Payment Event IDempotency

To prevent duplicate payment events from wallet callbacks:

```python
class PaymentEventService:
    def __init__(self, matrix_client, redis_client):
        self.matrix_client = matrix_client
        self.idempotency_store = redis_client
    
    async def handle_wallet_callback(
        self,
        callback_data: dict
    ) -> str:
        txn_id = callback_data['transaction_id']
        
        # Check idempotency key
        existing_event_id = await self.idempotency_store.get(
            f"payment_event:{txn_id}"
        )
        if existing_event_id:
            return existing_event_id
        
        # Create and send event
        event_id = await self.create_payment_event(callback_data)
        
        # Store idempotency key (24 hour TTL)
        await self.idempotency_store.setex(
            f"payment_event:{txn_id}",
            86400,
            event_id
        )
        
        return event_id
```

---

## 5. Authorization Framework

### 5.1 Scope Definitions

Scopes define the permissions granted to mini-apps. TMCP uses two types of scopes:

1. **TMCP Scopes**: Custom authorization for wallet, storage, messaging
2. **Matrix Scopes**: Standard Matrix API access (managed by MAS)

Each scope MUST be explicitly requested during authorization and approved by the user.

**Scope Naming Convention:**
```
<category>:<action>[:<resource>]
```

**Scope Sources:**

| Scope Type | Issuer | Purpose |
|------------|--------|---------|
| TMCP Scopes | TMCP Server | Wallet, storage, custom mini-app operations |
| Matrix Scopes | MAS | Matrix C-S API access, device management |
| Admin Scopes | MAS | Synapse admin API, MAS admin API |

### 5.2 TMCP Scopes

**Standard TMCP Scopes:**

| Scope | Description | Sensitivity | User Approval |
|-------|-------------|-------------|---------------|
| `user:read` | Read basic profile (name, avatar) | Low | Yes |
| `user:read:extended` | Read extended profile (status, bio) | Medium | Yes |
| `user:read:contacts` | Read friend list | High | Yes |
| `wallet:balance` | Read wallet balance | High | Yes |
| `wallet:pay` | Process payments | Critical | Yes (per transaction) |
| `wallet:history` | Read transaction history | High | Yes |
| `wallet:request` | Request payments from users | High | Yes |
| `messaging:send` | Send messages to rooms | High | Yes |
| `messaging:read` | Read message history | High | Yes |
| `storage:read` | Read mini-app storage | Low | No |
| `storage:write` | Write to mini-app storage | Low | No |
| `webhook:send` | Receive webhook callbacks | Medium | Yes |
| `room:create` | Create new rooms | High | Yes |
| `room:invite` | Invite users to rooms | High | Yes |

### 5.3 Matrix Scopes

Matrix scopes are issued by MAS and follow the naming convention defined in [MSC2967](https://github.com/matrix-org/matrix-spec-proposals/pull/2967).

**Standard Matrix Scopes:**

| Scope | Description | Issuer | Usage |
|-------|-------------|--------|-------|
| `urn:matrix:org.matrix.msc2967.client:api:*` | Full Matrix C-S API access | MAS | All Matrix operations |
| `urn:matrix:org.matrix.msc2967.client:device:[device_id]` | Device identification | MAS | Device-specific operations |
| `urn:synapse:admin:*` | Synapse admin API access | MAS | Admin operations |
| `urn:mas:admin` | MAS admin API access | MAS | MAS administration |

**Scope Mapping:**

| TMCP Operation | Requires TMCP Scope | Requires Matrix Scope |
|----------------|---------------------|----------------------|
| Send message | `messaging:send` | `urn:matrix:org.matrix.msc2967.client:api:*` |
| Read wallet | `wallet:balance` | (none) |
| Create room | `room:create` | `urn:matrix:org.matrix.msc2967.client:api:*` |
| Get user profile | `user:read` | `urn:matrix:org.matrix.msc2967.client:api:*` |

### 5.4 Scope Request Format

When requesting authorization, mini-apps specify both TMCP and Matrix scopes:

```http
POST /oauth2/device/authorization HTTP/1.1
Host: mas.tween.example
Content-Type: application/x-www-form-urlencoded

client_id=ma_shop_001
&scope=urn:matrix:org.matrix.msc2967.client:api:*+wallet:pay+messaging:send+storage:write
&miniapp_context={"launch_source": "chat_bubble", "room_id": "!abc123:tween.example"}
```

**Scope Parameter Format:**
- Space-separated list of scopes
- Both TMCP and Matrix scopes in same parameter
- TMCP scopes are validated by TMCP Server
- Matrix scopes are validated by MAS

### 5.5 Scope Validation

The TMCP Server MUST validate that all requested scopes are:

1. **Syntactically valid**: Follow scope naming conventions
2. **Registered**: Mini-app is approved for requested scopes
3. **Not escalated**: No more permissions than initial registration
4. **User-approved**: Sensitive scopes require user consent

**Validation Flow:**

```python
async def validate_scopes(
    self,
    requested_scopes: List[str],
    miniapp_id: str,
    user_id: str
) -> ValidationResult:
    """Validate requested scopes against mini-app registration."""
    
    # Get mini-app registered scopes
    registered_scopes = await self.get_registered_scopes(miniapp_id)
    
    # Check each requested scope
    valid_scopes = []
    denied_scopes = []
    
    for scope in requested_scopes:
        if scope in registered_scopes:
            # Check if user already approved this scope
            if self.is_user_sensitive_scope(scope) and \
               not await self.is_scope_approved(user_id, miniapp_id, scope):
                denied_scopes.append({
                    "scope": scope,
                    "reason": "user_approval_required"
                })
            else:
                valid_scopes.append(scope)
        else:
            denied_scopes.append({
                "scope": scope,
                "reason": "not_registered"
            })
    
    return ValidationResult(
        valid=valid_scopes,
        denied=denied_scopes
    )
```

### 5.6 Permission Revocation

Users MAY revoke permissions at any time. When permissions are revoked:

1. TMCP Server MUST invalidate all TEP tokens for that mini-app/user pair
2. MAS MUST revoke Matrix access tokens for that session
3. A Matrix state event MUST be created documenting the revocation:

```json
{
  "type": "m.room.tween.authorization",
  "state_key": "ma_shop_001",
  "content": {
    "authorized": false,
    "revoked_at": 1735689600,
    "revoked_scopes": ["wallet:pay", "messaging:send"],
    "reason": "user_initiated",
    "tmcp_scopes": ["wallet:pay", "messaging:send"],
    "matrix_scopes": ["urn:matrix:org.matrix.msc2967.client:api:*"]
  }
}
```

4. A webhook notification MUST be sent to the mini-app

**Revocation Flow:**

```
User Revokes Permission
         │
         ▼
┌─────────────────────────────────────┐
│ Client deletes local tokens         │
│ - Clear TEP from secure storage     │
│ - Clear MAS token from memory       │
└───────────────┬─────────────────────┘
                │
                ▼
┌─────────────────────────────────────┐
│ Notify TMCP Server                  │
│ POST /api/v1/auth/revoke            │
└───────────────┬─────────────────────┘
                │
                ▼
┌─────────────────────────────────────┐
│ TMCP Server:                        │
│ - Invalidate TEP tokens             │
│ - Create revocation event           │
│ - Send webhook notification         │
└───────────────┬─────────────────────┘
                │
                ▼
┌─────────────────────────────────────┐
│ Notify MAS:                         │
│ - Revoke Matrix access tokens       │
│ - Revoke refresh tokens             │
└─────────────────────────────────────┘
```

### 5.7 Authorization Context

The TEP token includes authorization context for granular permissions:

```json
{
  "scope": "wallet:pay messaging:send storage:write",
  "authorization_context": {
    "room_id": "!abc123:tween.example",
    "roles": ["member"],
    "permissions": {
      "can_send_messages": true,
      "can_invite_users": false,
      "can_edit_messages": false
    }
  },
  "approval_history": [
    {
      "scope": "wallet:pay",
      "approved_at": "2025-12-30T10:00:00Z",
      "approval_method": "transaction"
    }
  ]
}
```

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

#### 6.3.8 Client Implementation

Clients implementing P2P payments SHOULD:

1. Resolve recipient wallet status before showing payment UI
2. Handle cases where recipient has no wallet or suspended wallet
3. Include room_id for proper context validation
4. Provide user-friendly error messages for different failure scenarios

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

### 6.4 Wallet Verification Interface

#### 6.4.1 Overview

The TMCP protocol defines the **interface** for verification status queries. Wallet Service implementations MUST provide verification information via this interface but MAY implement verification levels according to local banking regulations and business requirements.

#### 6.4.2 Verification Status Endpoint

**Get Verification Status:**

```http
GET /wallet/v1/verification HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
```

**Response Format (Protocol-Defined):**
```json
{
  "level": <integer>,
  "level_name": <string>,
  "verified_at": <ISO8601_timestamp>,
  "limits": {
    "daily_limit": <decimal>,
    "transaction_limit": <decimal>,
    "monthly_limit": <decimal>,
    "currency": <string>
  },
  "features": {
    "p2p_send": <boolean>,
    "p2p_receive": <boolean>,
    "miniapp_payments": <boolean>
  },
  "can_upgrade": <boolean>
}
```

**Implementation Note:**
The specific verification levels, KYC requirements, and limit amounts are determined by Wallet Service implementations based on:
- Local banking regulations (e.g., CBN rules for Nigeria, FinCEN for US)
- Anti-money laundering (AML) requirements
- Business risk tolerance
- Jurisdiction-specific compliance frameworks

TMCP Server acts as a **protocol coordinator**, proxying requests to Wallet Service and forwarding responses to clients.

#### 6.4.3 Verification Status Validation

TMCP Server MUST validate verification status before allowing operations:

```javascript
async function validatePaymentEligibility(userId, amount, operation) {
  const verification = await getVerificationStatus(userId);
  
  // Check if operation is allowed
  if (operation === 'p2p_send' && !verification.features.p2p_send) {
    throw new Error('P2P_SEND_NOT_ALLOWED');
  }
  
  // Check amount limits
  if (amount > verification.limits.transaction_limit) {
    throw new Error('AMOUNT_EXCEEDS_LIMIT');
  }
  
  // Check daily limits (tracked by TMCP Server)
  const dailyUsed = await getDailyUsage(userId);
  if (dailyUsed + amount > verification.limits.daily_limit) {
    throw new Error('DAILY_LIMIT_EXCEEDED');
  }
  
  return true;
}
```

### 6.5 External Account Interface

#### 6.5.1 Overview

The TMCP protocol defines interfaces for external account operations, which are implemented by Wallet Service. These interfaces enable wallet funding and withdrawals through external financial accounts.

**Supported Account Types:**
- Bank accounts
- Debit/Credit cards
- Digital wallets
- Mobile money providers

#### 6.5.2 External Account Interface

The Wallet Service MUST implement these interfaces for external account operations:

```
LinkExternalAccount(user_id, account_details) → external_account_id
VerifyExternalAccount(account_id, verification_data) → status
FundWallet(user_id, source_account_id, amount) → funding_id
WithdrawToAccount(user_id, destination_account_id, amount) → withdrawal_id
```

#### 6.5.3 Protocol Response Format

All external account operations follow the standard response format defined in Section 12.1.

### 6.6 Withdrawal Interface

#### 6.6.1 Overview

The TMCP protocol defines interfaces for withdrawal operations, which are implemented by Wallet Service. These interfaces enable users to withdraw funds from their wallets.

#### 6.6.2 Withdrawal Interface

The Wallet Service MUST implement these interfaces for withdrawal operations:

```
InitiateWithdrawal(user_id, destination, amount) → withdrawal_id
ApproveWithdrawal(withdrawal_id, approval_data) → status
GetWithdrawalStatus(withdrawal_id) → withdrawal_details
```

#### 6.6.3 Protocol Response Format

All withdrawal operations follow the standard response format defined in Section 12.1.

---

## 7. Payment Protocol

This section defines the complete payment flow from initiation through completion, including peer-to-peer transfers, mini-app payments, and advanced features like multi-factor authentication and group gifts.

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

#### 7.5.6 Group Gift Atomicity

**Problem:** Multiple users opening gift simultaneously can cause race conditions and inconsistent state.

**Solution:** Database-level locking and atomic operations.

```sql
-- PostgreSQL Example
BEGIN;

-- Lock the gift row
SELECT * FROM group_gifts
WHERE gift_id = 'gift_abc123'
FOR UPDATE;

-- Check remaining count
IF remaining_count > 0 THEN
    -- Assign random amount
    UPDATE group_gifts
    SET remaining_count = remaining_count - 1
    WHERE gift_id = 'gift_abc123';

    -- Record opening
    INSERT INTO gift_openings (gift_id, user_id, amount)
    VALUES ('gift_abc123', '@bob:tween.example', 1250.00);
END IF;

COMMIT;
```

**Race Condition Prevention:**
- Use SELECT FOR UPDATE to lock gift row
- Validate remaining_count within transaction
- Return 409 CONFLICT if gift fully opened during request processing

**Concurrent Opening Handling:**
```javascript
async function openGift(giftId, userId) {
  try {
    const result = await db.transaction(async (trx) => {
      // Lock and check gift
      const gift = await trx('group_gifts')
        .where({ gift_id: giftId })
        .forUpdate()
        .first();

      if (!gift || gift.remaining_count <= 0) {
        throw new Error('GIFT_EMPTY');
      }

      // Calculate amount
      const amount = calculateRandomAmount(gift);

      // Update gift
      await trx('group_gifts')
        .where({ gift_id: giftId })
        .decrement('remaining_count', 1);

      // Record opening
      await trx('gift_openings').insert({
        gift_id: giftId,
        user_id: userId,
        amount: amount,
        opened_at: new Date()
      });

      return { amount, remaining: gift.remaining_count - 1 };
    });

    return result;
  } catch (error) {
    if (error.code === '23505') { // Unique constraint violation
      throw new Error('ALREADY_OPENED');
    }
    if (error.message === 'GIFT_EMPTY') {
      throw new Error('GIFT_EMPTY');
    }
    throw error;
  }
}
```

**Error Responses:**
```json
{
  "error": {
    "code": "GIFT_EMPTY",
    "message": "Gift has already been fully opened"
  }
}
```

```json
{
  "error": {
    "code": "ALREADY_OPENED",
    "message": "You have already opened this gift"
  }
}
```

### 7.6 Multi-Factor Authentication for Payments

#### 7.6.1 Overview

#### 7.6.2 MFA Challenge Request/Response

#### 7.6.3 MFA Response Submission

#### 7.6.4 Wallet Service MFA Interface

Wallet Service implementations that support MFA MUST provide challenge-response interfaces. TMCP Server acts as protocol coordinator and delegates MFA policy and validation to the Wallet Service.

**Interface Requirements:**
- Challenge generation and validation
- Method support negotiation (PIN, biometric, TOTP)
- Attempt limiting and lockout handling

The protocol defines standard credential formats but implementation details are Wallet Service specific.

### 7.7 Circuit Breaker Pattern for Payment Failures

#### 7.7.1 Overview

TMCP Servers MUST implement circuit breakers for Wallet Service calls to prevent cascade failures during payment processing. Circuit breakers provide resilience against temporary service outages and prevent system overload.

#### 7.7.2 Circuit States

**CLOSED** (Normal Operation):
- Requests pass through to Wallet Service
- Failure count monitored (sliding window of 10 requests)
- Success responses reset failure count

**OPEN** (Service Degraded):
- Triggered after 5 failures in 10 consecutive requests (50% threshold)
- All subsequent requests fail-fast with `503 SERVICE_UNAVAILABLE`
- Duration: 60 seconds before transitioning to HALF-OPEN

**HALF-OPEN** (Testing Recovery):
- After timeout, allow limited test requests (1 request per 10 seconds)
- If test requests succeed, transition to CLOSED
- If test requests fail, return to OPEN

#### 7.7.3 Circuit Breaker Algorithm

Circuit breakers operate in three states:

- **CLOSED**: Normal operation, requests pass through
- **OPEN**: Service degraded, requests fail fast after threshold failures
- **HALF_OPEN**: Testing recovery with limited requests

**Configuration Parameters:**
- Failure threshold: 5 failures in 10 requests
- Recovery timeout: 60 seconds
- Monitoring window: 10 requests

Implementation details are service-specific and not defined by this protocol.

#### 7.7.4 Circuit Breaker Metrics

TMCP Servers SHOULD expose circuit breaker metrics for monitoring:

```json
{
  "circuit_breakers": {
    "wallet_payments": {
      "state": "CLOSED",
      "failures_last_10_requests": 2,
      "total_requests": 1456,
      "success_rate": 0.987,
      "last_state_change": "2025-12-18T10:30:00Z"
    },
    "wallet_balance": {
      "state": "CLOSED",
      "failures_last_10_requests": 0,
      "total_requests": 8934,
      "success_rate": 0.999,
      "last_state_change": "2025-12-15T08:15:00Z"
    }
  }
}
```

#### 7.7.5 Error Response Format

When circuit breaker is open:

```http
HTTP/1.1 503 Service Unavailable
Retry-After: 60

{
  "error": {
    "code": "SERVICE_UNAVAILABLE",
    "message": "Payment service temporarily unavailable",
    "retry_after": 60,
    "circuit_state": "OPEN"
  }
}
```

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

### 9.3 Mini-App Review Process

#### 9.3.1 Automated Checks

**Static Analysis:**
1. CSP header validation
2. HTTPS-only resource loading
3. No hardcoded credentials
4. No obfuscated code (for non-commercial apps)
5. Dependency vulnerability scanning

**Example Report:**
```json
{
  "miniapp_id": "ma_shop_001",
  "status": "automated_review_complete",
  "checks": {
    "csp_valid": true,
    "https_only": true,
    "no_credentials": true,
    "no_obfuscation": false,  // ⚠️ Warning
    "dependencies_clean": true
  },
  "warnings": [
    {
      "type": "OBFUSCATED_CODE",
      "file": "main.js",
      "line": 1,
      "severity": "medium",
      "message": "Code appears obfuscated. Provide source maps for verification."
    }
  ]
}
```

#### 9.3.2 Manual Review Criteria

**Security Review:**
- [ ] Permissions justified (no excessive scope requests)
- [ ] Payment flows clearly disclosed to users
- [ ] Data collection minimized and disclosed
- [ ] No attempts to fingerprint devices
- [ ] No social engineering patterns

**Content Review:**
- [ ] Complies with platform policies
- [ ] No illegal content or services
- [ ] Age-appropriate content
- [ ] Clear privacy policy
- [ ] Terms of service provided

**Business Review:**
- [ ] Legitimate business entity
- [ ] Contact information verified
- [ ] Payment processor approved (if applicable)
- [ ] Refund policy clear

#### 9.3.3 Review Timeline

| Mini-App Type | Automated | Manual | Total |
|---------------|-----------|--------|-------|
| Official | Instant | N/A | Instant |
| Verified | 1 hour | 2-5 days | 2-5 days |
| Community | 1 hour | 5-10 days | 5-10 days |
| Beta | 1 hour | Priority | 1-2 days |

#### 9.3.4 Appeal Process

If mini-app rejected:

```http
POST /mini-apps/v1/{miniapp_id}/appeal HTTP/1.1
Authorization: Bearer <DEVELOPER_TOKEN>
Content-Type: multipart/form-data

{
  "reason": "We have addressed the CSP issues and resubmit for review",
  "changes_made": [
    "Added strict CSP with nonce support",
    "Removed inline event handlers",
    "Updated privacy policy"
  ],
  "evidence": [<FILES>]
}
```

**Response:**
```json
{
  "appeal_id": "appeal_abc123",
  "status": "under_review",
  "estimated_resolution": "2025-12-20T10:00:00Z",
  "contact_email": "appeals@tween.example"
}
```

---

## 10. Communication Verbs

Having established the security and architectural foundations, this section defines the JSON-RPC communication protocol between mini-apps and the host application, along with supporting APIs for storage, capabilities, and WebView security.

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
  "context": {
    "room_id": "!abc123:tween.example",
    "space_id": "!workspace:tween.example",
    "launch_source": "chat_bubble"
  },
  "id": 1
}
```

**Context Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `room_id` | String | Yes | Matrix room where mini-app was launched |
| `space_id` | String | No | Parent space/workspace identifier |
| `launch_source` | String | No | How mini-app was launched (chat_bubble, direct_link, etc.) |

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

### 10.4 WebView Security Requirements

Mini-apps execute within sandboxed WebViews that MUST implement security hardening to prevent XSS attacks, unauthorized resource access, and data leakage.

#### 10.4.1 Mandatory Security Controls

**File and Network Access:**
- File access MUST be disabled (`allowFileAccess: false`)
- Universal file access MUST be disabled
- Mixed content MUST be blocked
- External navigation MUST be validated against whitelist

**JavaScript and Content:**
- JavaScript execution MUST be controlled by mini-app manifest
- Content Security Policy (CSP) MUST be enforced
- Inline scripts and eval() MUST be prohibited
- Safe browsing checks MUST be enabled

**Platform-Specific Requirements:**
- iOS: `limitsNavigationsToAppBoundDomains` MUST be enabled
- Android: `setMixedContentMode(MIXED_CONTENT_NEVER_ALLOW)` MUST be set
- Debugging features MUST be disabled in production builds

Implementation details for each platform are provided in Appendix C.

#### 10.4.2 Content Security Policy

**ALL mini-apps MUST include CSP meta tag with minimum requirements:**

```html
<meta http-equiv="Content-Security-Policy" content="
  default-src 'self';
  script-src 'self' https://cdn.tween.example;
  connect-src 'self' https://tmcp.example.com;
  frame-ancestors 'none';
  upgrade-insecure-requests;
">
```

**Host Application Responsibilities:**
1. Generate unique nonce for script-src when JavaScript is enabled
2. Validate mini-app CSP meets minimum security requirements
3. Reject mini-apps with overly permissive policies

#### 10.4.3 JavaScript Bridge Security

**postMessage Communication MUST:**

1. **Origin Validation:** Mini-apps MUST specify target origin in postMessage calls
2. **Source Validation:** Host application MUST validate message source and origin
3. **Input Sanitization:** All message data MUST be treated as untrusted input
4. **Rate Limiting:** Host application MUST implement per-origin rate limiting

Message format and validation requirements are defined in Section 10.1.

#### 10.4.4 Additional Security Requirements

**URL Validation:** All navigation requests MUST be validated against domain whitelist and HTTPS requirements.

**Sensitive Data Protection:** Tokens and sensitive data MUST NOT be injected into WebView JavaScript context.

**Certificate Pinning:** RECOMMENDED for high-security deployments to prevent man-in-the-middle attacks.

**Lifecycle Management:** Sensitive data MUST be cleared when WebView is paused or destroyed.

Detailed implementation examples for all platforms are provided in Appendix C.

#### 10.4.5 Secure Communication Patterns

**NEVER inject sensitive data into WebView:**

```java
// ❌ WRONG - Exposes token to JavaScript
webView.loadUrl("javascript:window.tepToken = '" + tepToken + "';");

// ✓ CORRECT - Use secure postMessage
JSONObject message = new JSONObject();
message.put("type", "TMCP_INIT_SUCCESS");
message.put("user_id", userId);
// Do NOT include token in message

webView.evaluateJavascript(
    "window.postMessage(" + message.toString() + ", '*');",
    null
);
```

#### 10.4.6 Certificate Pinning

**For high-security mini-apps, implement certificate pinning:**

```kotlin
val certificatePinner = CertificatePinner.Builder()
    .add("tmcp.example.com", "sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")
    .add("api.example.com", "sha256/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=")
    .build()

val client = OkHttpClient.Builder()
    .certificatePinner(certificatePinner)
    .build()
```

#### 10.4.7 WebView Lifecycle Management

**Clear sensitive data on lifecycle events:**

```java
@Override
protected void onPause() {
    super.onPause();

    // Clear cache on pause
    webView.clearCache(true);
    webView.clearFormData();

    // Clear history if mini-app handles payments
    if (isSensitiveApp) {
        webView.clearHistory();
    }
}

@Override
protected void onDestroy() {
    super.onDestroy();

    // Complete cleanup
    webView.clearCache(true);
    webView.clearHistory();
    webView.clearFormData();
    webView.removeAllViews();
    webView.destroy();
}
```

### 10.5 Capability Negotiation

#### 10.5.1 Overview

Capability negotiation allows mini-apps to discover available host application features and APIs before attempting to use them. This prevents runtime errors and enables graceful degradation for missing features.

#### 10.5.2 Get Supported Features

**Request:**
```http
GET /api/v1/capabilities HTTP/1.1
Host: tmcp.example.com
Authorization: Bearer <TEP_TOKEN>
```

**Response:**
```json
{
  "capabilities": {
    "camera": {
      "available": true,
      "requires_permission": true,
      "supported_modes": ["photo", "qr_scan", "video"]
    },
    "location": {
      "available": true,
      "requires_permission": true,
      "accuracy": "high"
    },
    "payment": {
      "available": true,
      "providers": ["wallet", "card"],
      "max_amount": 50000.00
    },
    "storage": {
      "available": true,
      "quota_bytes": 10485760,
      "persistent": true
    },
    "messaging": {
      "available": true,
      "rich_cards": true,
      "file_upload": true
    },
    "biometric": {
      "available": true,
      "types": ["fingerprint", "face", "pin"]
    }
  },
  "platform": {
    "client_version": "2.1.0",
    "platform": "ios",
    "tmcp_version": "1.0"
  },
  "features": {
    "group_gifts": true,
    "p2p_transfers": true,
    "miniapp_payments": true
  }
}
```

#### 10.5.3 Capability Categories

| Category | Description | Example Use Cases |
|----------|-------------|-------------------|
| `camera` | Camera access for QR codes, photos | Payment QR codes, identity verification |
| `location` | GPS/location services | Location-based services, delivery tracking |
| `payment` | Payment processing capabilities | E-commerce, service payments |
| `storage` | Local data persistence | Shopping carts, user preferences |
| `messaging` | Rich messaging features | Interactive cards, file sharing |
| `biometric` | Biometric authentication | Payment authorization, secure login |

#### 10.5.4 Server-Side Validation

TMCP Servers SHOULD validate capability requests against:
1. **TEP Token Scope**: Ensure mini-app has required OAuth scopes
2. **Platform Support**: Check if client platform supports requested features
3. **Rate Limits**: Apply rate limiting to capability queries (100 per minute recommended)

---

## 11. Security Considerations

### 11.1 Transport Security

- TLS 1.3 REQUIRED for all communications
- Certificate pinning RECOMMENDED for mobile clients
- HSTS with `max-age` >= 31536000 REQUIRED

### 11.2 Authentication Security

**Token Security:**
- TEP tokens (JWT): 24 hours validity (RECOMMENDED)
- MAS access tokens: 5 minutes validity (per MAS specification)
- Refresh tokens: 30 days validity (RECOMMENDED)
- Tokens MUST be stored in secure storage (Keychain/KeyStore)
- Tokens MUST NOT be logged
- MAS access tokens MUST be stored in memory only, never persisted

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

### 11.4 Enhanced Rate Limiting

#### 11.4.1 Per-Endpoint Rate Limits

| Endpoint Category | Limit | Window | Burst | HTTP Status |
|-------------------|-------|--------|-------|-------------|
| **Authentication** |
| Device code request | 20 | 1 min | 5 | 429 |
| Token generation | 10 | 1 min | 3 | 429 |
| Token refresh | 20 | 1 hour | 5 | 429 |
| TEP validation | 1000 | 1 min | 100 | 429 |
| **Payments** |
| Payment initiation | 5 | 1 min | 0 | 429 |
| Payment authorization | 3 | 1 min | 0 | 429 |
| Failed payments | 5 | 5 min | 0 | 429 → 403 (locked) |
| P2P transfers | 10 | 1 hour | 3 | 429 |
| **Wallet Operations** |
| Balance query | 60 | 1 min | 10 | 429 |
| Transaction history | 30 | 1 min | 5 | 429 |
| User resolution | 100 | 1 min | 20 | 429 |
| **Storage Operations** |
| GET/SET/DELETE | 100 | 1 min | 20 | 429 |
| Batch operations | 10 | 1 min | 2 | 429 |
| **Mini-App Registry** |
| App registration | 5 | 1 day | 0 | 429 |
| App updates | 10 | 1 hour | 0 | 429 |

#### 11.4.2 Rate Limiting Algorithm

**Token Bucket Implementation:**

```python
import time
from collections import defaultdict

class RateLimiter:
    def __init__(self, rate, capacity, burst=0):
        self.rate = rate  # tokens per second
        self.capacity = capacity
        self.burst = burst
        self.buckets = defaultdict(lambda: {
            'tokens': capacity + burst,
            'last_update': time.time()
        })

    def allow_request(self, key):
        now = time.time()
        bucket = self.buckets[key]

        # Refill tokens based on time elapsed
        elapsed = now - bucket['last_update']
        bucket['tokens'] = min(
            self.capacity + self.burst,
            bucket['tokens'] + elapsed * self.rate
        )
        bucket['last_update'] = now

        # Check if request allowed
        if bucket['tokens'] >= 1:
            bucket['tokens'] -= 1
            return True, self.capacity + self.burst - bucket['tokens']
        else:
            retry_after = (1 - bucket['tokens']) / self.rate
            return False, retry_after

# Usage
payment_limiter = RateLimiter(rate=5/60, capacity=5, burst=0)  # 5 per minute

def process_payment(user_id, payment_data):
    allowed, info = payment_limiter.allow_request(user_id)

    if not allowed:
        raise RateLimitError(f"Retry after {info:.1f} seconds")

    # Process payment
    return execute_payment(payment_data)
```

#### 11.4.3 Distributed Rate Limiting

For multi-instance TMCP Server deployments, use Redis:

```python
import redis

class DistributedRateLimiter:
    def __init__(self, redis_client, key_prefix, rate, window):
        self.redis = redis_client
        self.key_prefix = key_prefix
        self.rate = rate
        self.window = window

    def allow_request(self, identifier):
        key = f"{self.key_prefix}:{identifier}"
        now = time.time()
        window_start = now - self.window

        # Remove old entries
        self.redis.zremrangebyscore(key, 0, window_start)

        # Count requests in current window
        count = self.redis.zcard(key)

        if count < self.rate:
            # Add new request
            self.redis.zadd(key, {str(now): now})
            self.redis.expire(key, int(self.window) + 1)
            return True, self.rate - count - 1
        else:
            # Get oldest request in window
            oldest = self.redis.zrange(key, 0, 0, withscores=True)[0]
            retry_after = oldest[1] + self.window - now
            return False, retry_after
```

#### 11.4.4 Rate Limit Response Headers

```http
HTTP/1.1 200 OK
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 87
X-RateLimit-Reset: 1704067260
X-RateLimit-Reset-After: 42
X-RateLimit-Burst: 20
X-RateLimit-Burst-Remaining: 15

HTTP/1.1 429 Too Many Requests
Retry-After: 42
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1704067302

{
  "error": {
    "code": "RATE_LIMIT_EXCEEDED",
    "message": "Too many requests",
    "retry_after": 42,
    "limit": 100,
    "window": "1 minute"
  }
}
```

#### 11.4.5 Account Suspension on Abuse

**Trigger Conditions:**
- 10+ rate limit violations in 1 hour
- 50+ failed payment attempts in 24 hours
- Suspected automated abuse patterns

**Response:**
```json
{
  "error": {
    "code": "ACCOUNT_SUSPENDED",
    "message": "Account temporarily suspended due to abuse",
    "suspended_until": "2025-12-18T16:00:00Z",
    "reason": "repeated_rate_limit_violations",
    "appeal_url": "https://tween.example/appeal"
  }
}
```

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

### 13.1 Controlled Federation Model

TMCP deployments typically operate in controlled federation environments:

- Federation limited to trusted infrastructure
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

### 16.10 OAuth Server Implementation with MAS

**Recommended Implementation: Matrix Authentication Service (MAS)**

For production deployments, TMCP implementations MUST use Matrix Authentication Service (MAS) as the OAuth 2.0 authorization server, as defined in MSC3861. MAS provides native Matrix integration with the following advantages:

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
          │ OAuth 2.0              ├──→ MAS (Authentication)
          │ Delegation                │   Token Management
          │                          ├──→ User Sessions
          │                          └──→ Scope Policy
          │
          ↓
┌──────────────────────────────────────────────────┐
│            MATRIX AUTHENTICATION SERVICE          │
│  ┌────────────────────────────────────────────┐  │
│  │ OAuth 2.0 / OIDC Provider              │  │
│  │ Token Issuance & Refresh                │  │
│  │ User Authentication (Device/Auth Code)  │  │
│  │ Scope Management                        │  │
│  └────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────┘
```

**MAS Configuration for TMCP:**

**TMCP Server Client Registration:**

```yaml
# MAS configuration (config.yaml)
clients:
  - client_id: ma_tmcp_server
    client_auth_method: client_secret_post
    client_secret_file: /run/secrets/mas_client_secret
    grant_types:
      - authorization_code
      - urn:ietf:params:oauth:grant-type:device_code
      - refresh_token
      - urn:ietf:params:oauth:grant-type:reverse_1
    scope:
      - openid
      - urn:matrix:org.matrix.msc2967.client:api:*
      - urn:synapse:admin:*
```

**Mini-App Client Registration:**

Each mini-app MUST be registered in MAS:

```yaml
clients:
  - client_id: ma_shop_001
    client_auth_method: client_secret_post
    client_secret_file: /run/secrets/ma_shop_001_secret
    redirect_uris:
      - https://shop.miniapp.example.com/callback
    grant_types:
      - authorization_code
      - urn:ietf:params:oauth:grant-type:device_code
      - refresh_token
    scope:
      - openid
      - urn:matrix:org.matrix.msc2967.client:api:*
```

**Token Flow:**

1. Mini-app initiates OAuth 2.0 device authorization or authorization code flow
2. User authenticates via MAS (includes MFA if required)
3. MAS issues access token and refresh token to mini-app
4. Mini-app exchanges token for TEP via TMCP Server
5. TEP used for TMCP-specific operations
6. Matrix operations use MAS access token via proxy

**Benefits of MAS Integration:**

1. **Native Matrix Support**: OAuth 2.0 designed for Matrix protocol
2. **User Identity**: Unified Matrix user identity across all operations
3. **Token Management**: Automatic token rotation and refresh
4. **Security**: Industry-standard OAuth 2.0 / OIDC compliance
5. **Scalability**: Horizontal scaling with PostgreSQL backend
6. **Device Authorization**: Native support for login via QR code
7. **Session Management**: Comprehensive session lifecycle control

**Implementation Notes:**

- TMCP Server acts as OAuth 2.0 resource server
- MAS handles authorization server responsibilities
- Token validation via MAS introspection endpoint
- TMCP-specific scopes managed by TMCP Server
- MFA policies enforced at MAS level

This integration maintains TMCP's security model while leveraging MAS's native Matrix authentication capabilities.

---

## 17. Appendices

### Appendix A: Complete Protocol Flow Example

**Scenario:** User purchases item from mini-app in chat

**In-Chat Payment Flow:**

```
Step 1: Authentication (Device Authorization Grant)
─────────────────────────────────────────────────
1. Mini-app initiates device authorization
   POST /oauth2/device/authorization
   client_id=ma_shop_001

2. MAS returns device code and user code
   { "device_code": "...", "user_code": "WDJB-MJHR", ... }

3. User visits MAS, enters code, authenticates

4. Mini-app polls for token
   POST /oauth2/token grant_type=device_code

5. MAS returns tokens
   {
     "access_token": "opaque_mas_token",
     "refresh_token": "refresh_token_xyz",
     "tep_token": "tep.jwt.token..."
   }

Step 2: Payment Request
───────────────────────
6. User adds item to cart, clicks "Buy"
7. Mini-app calls `tween.wallet.pay`
8. Client displays payment confirmation UI
9. User authorizes with biometric/PIN
10. Client signs payment with hardware key
11. Client sends signed payment to TMCP Server
    Authorization: Bearer tep.jwt.token

Step 3: Payment Processing
──────────────────────────
12. TMCP Server validates TEP token and signature
13. TMCP Server forwards payment to Wallet Service
14. Wallet Service executes transfer
15. Wallet Service sends callback to TMCP Server
    {
      "event": "payment.completed",
      "transaction_id": "txn_wallet_123",
      "amount": 15000.00,
      "currency": "USD",
      "sender": { "user_id": "@alice:tween.example" },
      "recipient": { "miniapp_id": "ma_shop_001" },
      "room_id": "!chat123:tween.example",
      "note": "Order #12345"
    }

Step 4: Payment Receipt in Chat
──────────────────────────────────────────────
16. TMCP Server creates payment event
    Event Type: m.tween.payment.completed
    Sender: @_tmcp_payments:tween.example (Virtual Payment Bot)
    Room: !chat123:tween.example

17. TMCP Server sends event to Matrix
    POST /_matrix/client/v3/rooms/!chat123:tween.example/send/m.tween.payment.completed
    Authorization: Bearer <AS_TOKEN>

    {
      "type": "m.tween.payment.completed",
      "content": {
        "msgtype": "m.tween.payment",
        "payment_type": "completed",
        "visual": { "card_type": "payment_receipt", "icon": "payment_completed" },
        "transaction": { "txn_id": "txn_wallet_123", "amount": 15000.00, "currency": "USD" },
        "sender": { "user_id": "@alice:tween.example", "display_name": "Alice" },
        "recipient": { "miniapp_id": "ma_shop_001", "name": "Shopping Assistant" },
        "note": "Order #12345",
        "timestamp": "2025-12-18T14:30:00Z"
      }
    }

18. Matrix Homeserver persists and distributes event

19. Client renders as rich payment card

Step 5: Webhook Notification
────────────────────────────
20. TMCP Server sends webhook to mini-app
    POST https://miniapp.example.com/webhooks/payment
    {
      "payment_id": "pay_abc123",
      "status": "completed",
      "transaction_id": "txn_wallet_123",
      "amount": 15000.00
    }

21. Mini-app processes order and confirms completion
```

**Visual Flow:**

```
┌─────────────────────────────────────────────────────────────────────┐
│                         CHAT ROOM                                    │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ [Message History]                                           │    │
│  │                                                             │    │
│  │  Alice: Hey, check out this product!                       │    │
│  │                                                             │    │
│  │  ┌─────────────────────────────────────────────────────┐   │    │
│  │  │ 💰 Payment Completed                                │   │    │
│  │  │ ─────────────────────────────────────────────────  │   │    │
│  │  │                                                       │   │    │
│  │  │  To: Shopping Assistant                              │   │    │
│  │  │  Amount: $15,000.00 USD                             │   │    │
│  │  │                                                       │   │    │
│  │  │  Note: Order #12345                                  │   │    │
│  │  │                                                       │   │    │
│  │  │  ───────────────────────────────                      │   │    │
│  │  │  Transaction ID: txn_wallet_123                      │   │    │
│  │  │  Dec 18, 2025 2:30 PM                                │   │    │
│  │  │                                     [View Details]   │   │    │
│  │  └─────────────────────────────────────────────────────┘   │    │
│  │                                                             │    │
│  │  Bob: Nice! Looks great!                                   │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

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

### Appendix C: WebView Implementation Details

#### Android WebView Configuration
```java
WebView miniAppWebView = findViewById(R.id.miniapp_webview);
WebSettings settings = miniAppWebView.getSettings();

// JavaScript - ONLY if mini-app explicitly requires it
settings.setJavaScriptEnabled(true);  // Default: false

// File Access - ALWAYS disable
settings.setAllowFileAccess(false);
settings.setAllowContentAccess(false);
settings.setAllowFileAccessFromFileURLs(false);
settings.setAllowUniversalAccessFromFileURLs(false);

// Geolocation - Require explicit permission
settings.setGeolocationEnabled(false);  // Enable only after user grants permission

// Database - Disable unless needed
settings.setDatabaseEnabled(false);
settings.setDomStorageEnabled(false);  // LocalStorage disabled by default

// Mixed Content - ALWAYS block
settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);

// WebView Debugging - MUST be disabled in production
if (!BuildConfig.DEBUG) {
    WebView.setWebContentsDebuggingEnabled(false);
}

// Safe Browsing - ALWAYS enable
SafeBrowsingApiHandler.initSafeBrowsing(context);
miniAppWebView.startSafeBrowsing(context, isSuccess -> {
    if (!isSuccess) {
        Log.e("TMCP", "Safe Browsing initialization failed");
    }
});
```

#### iOS WebView Configuration
```swift
let config = WKWebViewConfiguration()
let prefs = WKPreferences()

// JavaScript - ONLY if required
prefs.javaScriptEnabled = true  // Default: true on iOS
prefs.javaScriptCanOpenWindowsAutomatically = false

config.preferences = prefs

// File access - Restrict to specific domains
config.limitsNavigationsToAppBoundDomains = true

// Inline media playback
config.allowsInlineMediaPlayback = true
config.mediaTypesRequiringUserActionForPlayback = .all

let webView = WKWebView(frame: .zero, configuration: config)
```

#### URL Validation Example (Android)
```java
public boolean shouldOverrideUrlLoading(WebView view, String url) {
    Uri uri = Uri.parse(url);

    // Whitelist allowed domains
    List<String> allowedDomains = Arrays.asList(
        "miniapp.example.com",
        "cdn.tween.example",
        "tmcp.example.com"
    );

    String host = uri.getHost();
    if (host == null || !allowedDomains.contains(host)) {
        Log.w("TMCP", "Blocked unauthorized domain: " + host);
        return true;  // Prevent navigation
    }

    // Only allow HTTPS
    if (!"https".equals(uri.getScheme())) {
        Log.w("TMCP", "Blocked non-HTTPS URL: " + url);
        return true;
    }

    return false;  // Allow navigation
}
```

#### Sensitive Data Protection (Android)
```java
// ❌ WRONG - Exposes token to JavaScript
webView.loadUrl("javascript:window.tepToken = '" + tepToken + "';");

// ✓ CORRECT - Use secure postMessage
JSONObject message = new JSONObject();
message.put("type", "TMCP_INIT_SUCCESS");
message.put("user_id", userId);
// Do NOT include token in message

webView.evaluateJavascript(
    "window.postMessage(" + message.toString() + ", '*');",
    null
);
```

#### Certificate Pinning (Android)
```kotlin
val certificatePinner = CertificatePinner.Builder()
    .add("tmcp.example.com", "sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")
    .add("api.example.com", "sha256/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=")
    .build()

val client = OkHttpClient.Builder()
    .certificatePinner(certificatePinner)
    .build()
```

#### WebView Lifecycle Management (Android)
```java
@Override
protected void onPause() {
    super.onPause();

    // Clear cache on pause
    webView.clearCache(true);
    webView.clearFormData();

    // Clear history if mini-app handles payments
    if (isSensitiveApp) {
        webView.clearHistory();
    }
}

@Override
protected void onDestroy() {
    super.onDestroy();

    // Complete cleanup
    webView.clearCache(true);
    webView.clearHistory();
    webView.clearFormData();
    webView.removeAllViews();
    webView.destroy();
}
```

### Appendix D: Webhook Signature Verification

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

**End of TMCP-001**