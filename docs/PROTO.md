# Tween Mini-App Communication Protocol (TMCP)

**Document ID:** TMCP-001  
**Category:** Proposed Standard  
**Date:** December 2025  
**Authors:** Ezeani Emmanuel
**Handle:** @mona:tween.im

---

## Abstract

This document specifies the Tween Mini-App Communication Protocol (TMCP), a comprehensive protocol for secure communication between instant messaging applications and third-party mini-applications. Built as an isolated Application Service layer on the Matrix protocol, TMCP provides authentication, authorization, and wallet-based payment processing without modifying Matrix/Synapse core code. The protocol enables an integrated application platform with wallet services, instant peer-to-peer transfers, mini-app payments, and social commerce. TMCP operates within Matrix's federation framework but assumes deployment in controlled federation environments for enhanced security.

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

Modern instant messaging platforms increasingly serve as integrated application platforms that integrate communication, commerce, and financial services. This specification defines a protocol that enables such functionality while maintaining protocol isolation from the underlying communication infrastructure.

The Tween Mini-App Communication Protocol (TMCP) addresses the following requirements:

- **Protocol Isolation**: Extensions to Matrix without core modifications
- **Wallet-Centric Architecture**: Integrated financial services as first-class citizens
- **Peer-to-Peer Transactions**: Direct value transfer between users within conversations
- **Mini-Application Integration**: Third-party application integration with standardized APIs
- **Controlled Federation**: Internal server infrastructure with centralized wallet management

### 1.2 Design Goals

**MUST Requirements:**
- No modification to Matrix/Synapse core protocol
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

TMCP Server MUST register as a Matrix Application Service with:

| Parameter | Required | Description |
|-----------|-----------|-------------|
| `id` | Yes | Unique identifier for the AS (e.g., `tween-miniapps`) |
| `url` | Yes | URL where TMCP Server is accessible (e.g., `https://tmcp.internal.example.com`) |
| `sender_localpart` | Yes | Localpart for AS user (e.g., `_tmcp`) |
| `namespaces.users` | Yes | Regex patterns for AS-controlled users, MUST be exclusive |
| `namespaces.aliases` | Yes | Regex patterns for AS-controlled room aliases, MUST be exclusive |
| `rate_limited` | No | SHOULD be `false` for TMCP Server |

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

The TMCP Server MUST be configured with MAS client credentials for token operations:

| Configuration | Required | Value |
|--------------|-----------|--------|
| Token URL | Yes | MAS OAuth 2.0 token endpoint |
| Introspection URL | Yes | MAS OAuth 2.0 introspection endpoint |
| Revocation URL | Yes | MAS OAuth 2.0 revocation endpoint |
| Client ID | Yes | TMCP Server identifier registered with MAS |
| Client Secret | Yes | Secret for TMCP Server client authentication |
| Default Scopes | Yes | MUST include Matrix C-S API scope |

Tokens from MAS MUST be cached with appropriate TTL (4-5 minutes recommended) to reduce introspection requests.

**TEP Token Issuance Requirements:**

The TMCP Server MUST implement an OAuth 2.0 token endpoint at `/oauth2/token` for TEP token issuance. The endpoint MUST:

1. **Client Authentication**:
   - Validate `client_id` and `client_secret` against registered mini-app credentials
   - Reject requests with invalid credentials using HTTP 401 Unauthorized

2. **User Identification**:
   - Extract Matrix access token from request
   - Validate Matrix token via MAS introspection endpoint
   - Extract user identifier from `sub` claim in introspection response

3. **Token Claims**:
   The TEP token MUST include the following claims:

   | Claim | Required | Description |
   |-------|----------|-------------|
   | `iss` | Yes | TMCP Server URL |
   | `sub` | Yes | Matrix User ID |
   | `aud` | Yes | Mini-app client ID |
   | `exp` | Yes | Expiration time (24 hours from issuance) |
   | `iat` | Yes | Issuance timestamp |
   | `nbf` | Yes | Not before timestamp |
   | `jti` | Yes | Unique token identifier |
   | `token_type` | Yes | MUST be "tep_access_token" |
   | `client_id` | Yes | Mini-app client ID |
   | `azp` | Yes | Authorized party (same as client_id) |
   | `scope` | Yes | Space-separated granted scopes |
   | `wallet_id` | Yes | User's wallet identifier |
   | `session_id` | Yes | Session identifier |
   | `user_context` | No | User display information |
   | `miniapp_context` | No | Launch context information |
   | `mas_session` | Yes | Matrix session reference |

4. **Token Response**:
   - Return `access_token` with "tep." prefix followed by JWT
   - Return `token_type` as "Bearer"
   - Return `expires_in` as 86400 (24 hours)
   - Return `refresh_token` for TEP renewal
   - Return `scope` with authorized permissions
   - Return `user_id` and `wallet_id`

**Response Format:**

```json
{
  "access_token": "tep.eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "Bearer",
  "expires_in": 86400,
  "refresh_token": "rt_abc123",
  "scope": "user:read wallet:pay storage:write",
  "user_id": "@alice:utween.example",
  "wallet_id": "tw_alice_123"
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

TMCP implements a dual-token architecture that maintains separation of concerns:

1. **Matrix Access Token** (Opaque): Issued by MAS, used for Matrix C-S API operations
2. **TEP Token (JWT)**: Issued by TMCP Server, contains mini-app authorization claims

**Authentication Flow Selection:**

```
User State                     Flow
─────────────────────────────────────────────────────────────
Already logged into Element → Matrix Session Delegation
New user / new session      → Device Authorization Grant
Web mini-app                → Authorization Code Grant
```

**Dual-Token Separation:**

| Token Type | Issuer | Purpose | Storage | Lifetime |
|------------|--------|---------|---------|----------|
| TEP (JWT) | TMCP Server | TMCP operations (wallet, payments, storage) | Keychain/Encrypted | 24 hours |
| MAS Access Token | MAS | Matrix C-S API operations | Memory only | 5 minutes |

This separation ensures:
- Mini-apps have rich authorization claims for TMCP operations
- Matrix operations use standard OAuth 2.0 tokens managed by MAS
- Security is maintained with memory-only storage for sensitive Matrix tokens
- Token refresh is handled transparently without complex client logic

### 4.2 Matrix Authentication Service (MAS) Integration

Per [Matrix Specification v1.15](https://spec.matrix.org/v1.15/), TMCP deployments MUST integrate with Matrix Authentication Service as the OAuth 2.0 authorization server for Matrix operations.

**MAS Endpoints** (as defined in Matrix Client-Server API):

| Endpoint | Purpose | Specification |
|----------|---------|---------------|
| `/.well-known/openid-configuration` | Server metadata discovery | OAuth 2.0 Discovery |
| `/oauth2/authorize` | Authorization endpoint | RFC 6749 §3.1 |
| `/oauth2/token` | Token endpoint | RFC 6749 §3.2 |
| `/oauth2/introspect` | Token introspection | RFC 7662 §2.1 |
| `/oauth2/revoke` | Token revocation | RFC 7009 §2.1 |

**TMCP Server MAS Client Registration:**

TMCP Server MUST be registered as a confidential client in MAS with:

| Parameter | Required | Value/Description |
|-----------|-----------|-------------------|
| `client_auth_method` | Yes | `client_secret_post` |
| `grant_types` | Yes | MUST include: `urn:ietf:params:oauth:grant-type:token-exchange`, `refresh_token` |
| `scope` | Yes | MUST include: `urn:matrix:org.matrix.msc2967.client:api:*` |

### 4.3 Authentication Flows

#### 4.3.1 Matrix Session Delegation

**Purpose**: This section defines the Matrix Session Delegation flow, which enables mini-app authentication for users with existing Matrix sessions without additional user interaction.

**Prerequisites:**
- User MUST have active Matrix session in Element X/Classic
- Client MUST have valid Matrix access token
- TMCP Server MUST be registered as MAS client

**Flow Diagram:**

```
User Logged Into Element X
  │
  │ User taps mini-app in chat
  ↓
┌────────────────────────────────────────────┐
│ Element X Client                           │
│ - Has Matrix access_token                  │
│ - Has user_id from session                 │
└───────────────────┬────────────────────────┘
                    │
                    │ POST /oauth2/token
                    │ grant_type=urn:ietf:params:oauth:grant-type:token-exchange
                    │ subject_token=<matrix_access_token>
                    │ client_id=ma_shop_001
                    ↓
┌────────────────────────────────────────────┐
│ TMCP Server                                │
│                                            │
│ 1. Validate subject_token with MAS         │
│    POST /oauth2/introspect                 │
│                                            │
│ 2. Check mini-app scopes                   │
│    - Pre-approved scopes: auto-grant       │
│    - Sensitive scopes: require consent     │
│                                            │
│ 3. Issue TEP token with approved scopes    │
└───────────────────┬────────────────────────┘
                    │
                    │ Response:
                    │ - access_token (TEP)
                    │ - refresh_token
                    │ - matrix_access_token (new, short-lived)
                    ↓
┌────────────────────────────────────────────┐
│ Mini-App Launches                          │
│ - TEP token in secure storage              │
│ - Matrix token in memory only              │
│ - No user interaction required ✓           │
└────────────────────────────────────────────┘
```

**Request Format:**

```http
POST /oauth2/token HTTP/1.1
Host: tmcp.example.com
Content-Type: application/x-www-form-urlencoded

grant_type=urn:ietf:params:oauth:grant-type:token-exchange
&subject_token=<MATRIX_ACCESS_TOKEN>
&subject_token_type=urn:ietf:params:oauth:token-type:access_token
&client_id=ma_shop_001
&client_secret=<CLIENT_SECRET>
&scope=user:read wallet:pay storage:write
&requested_token_type=urn:tmcp:params:oauth:token-type:tep
&miniapp_context={"room_id":"!abc:tween.example","launch_source":"chat_bubble"}
```

**Token Exchange Parameters:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| `grant_type` | Yes | MUST be `urn:ietf:params:oauth:grant-type:token-exchange` |
| `subject_token` | Yes | Matrix access token from Element session |
| `subject_token_type` | Yes | MUST be `urn:ietf:params:oauth:token-type:access_token` |
| `client_id` | Yes | Mini-app client identifier |
| `client_secret` | Yes | Mini-app client secret |
| `scope` | No | Space-separated TMCP scopes requested |
| `requested_token_type` | No | MUST be `urn:tmcp:params:oauth:token-type:tep` if provided |
| `miniapp_context` | No | JSON object with launch context (room_id, etc.) |

**TMCP Server Processing Requirements:**

The TMCP Server MUST process token exchange requests in the following sequence:

1. **Subject Token Validation**: The server MUST introspect the subject_token at the MAS introspection endpoint using TMCP Server's client credentials. The introspection response MUST indicate `active: true` and contain a valid `sub` claim representing the Matrix User ID.

2. **Client Authentication**: The server MUST validate the client_id and client_secret provided in the request against the registered mini-app credentials.

3. **Scope Authorization**: For each requested scope:
   - If the scope is registered as a pre-approved scope for the mini-app, authorize without requiring user consent
   - If the scope is a sensitive scope registered for the mini-app, check if the user has previously approved this scope for this mini-app
   - If the scope is not registered for the mini-app, deny authorization
   - If the scope requires user consent and has not been previously approved, mark for consent requirement

4. **Consent Handling**: If any scopes require user consent, the server MUST return a `consent_required` error response as specified below. The response MUST include both consent_required_scopes and pre_approved_scopes.

5. **Wallet Resolution**: The server MUST obtain or create a wallet ID for the authenticated user.

6. **TEP Token Issuance**: The server MUST issue a TEP token as defined in Section 4.4, containing:
   - The Matrix User ID from the subject_token
   - The authorized scopes
   - The user's wallet ID
   - The mini-app client ID
   - The mini-app context if provided
   - A session identifier

7. **Matrix Token Exchange**: The server MUST obtain a new Matrix access token from MAS via the OAuth 2.0 token exchange grant, using the subject_token as input and requesting Matrix C-S API scopes.

8. **Response Composition**: The server MUST return both the TEP token and the new Matrix access token in the response.

**Success Response:**

```json
{
  "access_token": "tep.eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "Bearer",
  "expires_in": 86400,
  "refresh_token": "rt_abc123",
  "scope": "user:read wallet:pay storage:write",
  "matrix_access_token": "syt_opaque_matrix_token",
  "matrix_expires_in": 300,
  "user_id": "@alice:tween.example",
  "wallet_id": "tw_user_12345",
  "delegated_session": true
}
```

**Consent Required Response:**

```json
{
  "error": "consent_required",
  "error_description": "User must approve sensitive scopes",
  "consent_required_scopes": ["wallet:pay"],
  "pre_approved_scopes": ["user:read", "storage:write"],
  "consent_ui_endpoint": "/oauth2/consent?session=xyz123"
}
```

**Consent Flow Requirements:**

When the server returns a `consent_required` error response, clients MUST obtain user consent for the requested sensitive scopes before re-attempting authentication. Clients SHOULD display native user interface elements to obtain consent rather than redirecting to external URLs, as this would interrupt the authentication flow without requiring user interaction with existing session.

The consent UI MUST clearly indicate:
- The mini-app requesting access
- The specific permissions being requested
- Any permissions already approved

After obtaining user consent, the client MUST submit the consent approval to the server endpoint specified in `consent_ui_endpoint`.

**Matrix Token Introspection:**

TMCP Server validates Matrix tokens using MAS introspection endpoint as defined in [RFC 7662](https://datatracker.ietf.org/doc/html/rfc7662):

```http
POST /oauth2/introspect HTTP/1.1
Host: mas.tween.example
Content-Type: application/x-www-form-urlencoded
Authorization: Basic base64(tmcp_server_001:client_secret)

token=syt_matrix_access_token
```

**Introspection Response:**

```json
{
  "active": true,
  "scope": "urn:matrix:org.matrix.msc2967.client:api:*",
  "client_id": "element_web_001",
  "sub": "@alice:tween.example",
  "exp": 1735689900,
  "iat": 1735689600
}
```

#### 4.3.2 Device Authorization Grant (New Users)

For users without an active Element session, use Device Authorization Grant ([RFC 8628](https://datatracker.ietf.org/doc/html/rfc8628)):

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

The client MUST display the `user_code` and `verification_uri` to the user in a user interface. The user then visits `verification_uri` and enters the `user_code` to authorize the device.

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

**Step 6: Exchange MAS Token for TEP**

After receiving Matrix access token from MAS, client MUST exchange it for TEP using Matrix Session Delegation flow as specified in Section 4.3.1.

#### 4.3.3 Authorization Code Grant (Web Mini-Apps)

For web-based mini-apps running in browser, use Authorization Code Flow with PKCE ([RFC 7636](https://datatracker.ietf.org/doc/html/rfc7636)).

**Step 1: Generate PKCE Parameters**

Client MUST generate a code verifier, code challenge, and state parameter as per RFC 7636:
- `code_verifier`: Cryptographically random string with sufficient entropy
- `code_challenge`: BASE64URL-encoded SHA256 hash of `code_verifier`
- `state`: Cryptographically random string to prevent CSRF attacks

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
  },
  "delegated_from": "matrix_session",
  "matrix_session_ref": {
    "device_id": "GHTYAJCE",
    "session_id": "mas_session_abc"
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
| `delegated_from` | No | Session delegation source (e.g., "matrix_session") |
| `matrix_session_ref` | No | Matrix session details (device_id, session_id) |

### 4.5 Client-Side Token Management

#### 4.5.1 Secure Storage Requirements

**TEP Token Storage:**

TEP tokens MUST be stored in platform-specific secure storage:

| Platform | Storage Mechanism |
|----------|------------------|
| iOS | Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` |
| Android | EncryptedSharedPreferences |
| Web | localStorage with encryption (implementation-defined) |

TEP tokens MUST be protected against:
- Unauthorized access from other apps
- Extraction from device storage
- Cross-site scripting attacks (for web applications)

**Matrix Access Token Storage:**

Matrix access tokens MUST be stored in memory only and MUST NOT be persisted to disk or localStorage. Memory storage MUST clear tokens when application terminates or transitions to background state.

**Refresh Token Storage:**

Refresh tokens MUST be stored with same security requirements as TEP tokens. Refresh tokens MUST be rotated on each use.

#### 4.5.2 Token Lifecycle Management

**Initialization:**

Upon application launch, clients MUST:
1. Check for valid TEP token in secure storage
2. If TEP token is missing or expired, initiate appropriate authentication flow
3. If valid TEP token exists, refresh Matrix access token using refresh token

**TEP Expiration:**

When TEP token expires, clients MUST initiate full re-authentication using Device Authorization Grant or Authorization Code Grant. TEP tokens cannot be refreshed directly.

**Logout:**

Clients MUST:
1. Revoke refresh token at MAS endpoint
2. Remove all tokens from secure storage
3. Clear all in-memory tokens
4. Clear any cached user data

### 4.6 TMCP Server Authentication Middleware

**Token Validation Requirements**:

TEP tokens MUST be validated using RSA-PSS signature verification with TMCP Server public key. The following claims MUST be verified:

| Claim | Verification |
|--------|--------------|
| `iss` | MUST equal TMCP Server URL |
| `aud` | MUST equal "tmcp-server" or mini-app client_id |
| `exp` | MUST be in the future |
| `nbf` | MUST be in the past or present |
| `iat` | MUST be in the past or present |
| `token_type` | MUST equal "tep_access_token" |

**Scope Authorization**:

The server MUST verify that required scope for endpoint is present in TEP token's scope claim. If scope is missing, server MUST return 403 Forbidden.

**Matrix Token Management**:

TMCP Server MUST maintain valid Matrix access tokens for each session. Token refresh MUST use OAuth 2.0 refresh_token grant and MUST be obtained from MAS endpoint.

**Matrix Request Proxying**:

When TMCP Server proxies requests to Matrix homeserver on behalf of authenticated user, it MUST:
- Obtain valid Matrix access token using stored refresh token
- Add Authorization header with Bearer token
- Forward request to Matrix homeserver endpoint
- Return response to mini-app

**Error Responses**:

| Condition | HTTP Status | Error |
|-----------|--------------|--------|
| Missing TEP token | 401 | "Missing TEP token" |
| Invalid TEP token | 401 | "Invalid or expired TEP token" |
| Missing required scope | 403 | "Missing required scope" |
| Failed Matrix token refresh | 401 | "Failed to refresh Matrix token" |

### 4.7 MAS Integration Requirements

#### 4.7.1 MAS Client Registration

The TMCP Server MUST be registered as a confidential client in MAS with the following capabilities:

| Parameter | Required | Value |
|-----------|-----------|--------|
| `client_auth_method` | Yes | `client_secret_post` |
| `grant_types` | Yes | MUST include: `urn:ietf:params:oauth:grant-type:token-exchange`, `refresh_token` |
| `scope` | Yes | MUST include: `urn:matrix:org.matrix.msc2967.client:api:*` |

#### 4.7.2 Mini-App Client Registration

Each mini-app MUST be registered in MAS with the following capabilities:

| Parameter | Required | Description |
|-----------|-----------|-------------|
| `client_auth_method` | Yes | MUST be `client_secret_post` |
| `redirect_uris` | Yes | For Authorization Code Grant |
| `grant_types` | Yes | MUST include: `authorization_code`, `urn:ietf:params:oauth:grant-type:device_code`, `urn:ietf:params:oauth:grant-type:token-exchange`, `refresh_token` |
| `scope` | Yes | MUST include: `urn:matrix:org.matrix.msc2967.client:api:*` |

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

#### 4.9.1 Comparison of Authentication Flows

| Feature | Matrix Session Delegation | Device Authorization | Authorization Code |
|---------|---------------------------|---------------------|-------------------|
| **Use Case** | Logged-in Element users | New users, no browser | Web mini-apps |
| **User Interaction** | None | Enter code on web | Browser redirect |
| **Time to Complete** | <1 second | 30-60 seconds | 10-20 seconds |
| **UX Quality** | Excellent | Good | Good |
| **Security** | High (token introspection) | High (device flow) | High (PKCE) |
| **Offline Support** | No (requires validation) | No (requires web) | No (requires web) |

#### 4.9.2 Token Validation

TMCP Server MUST validate Matrix tokens via MAS introspection on every token exchange request. Servers MUST:

1. Submit POST request to MAS `/oauth2/introspect` endpoint with Basic Authentication using TMCP Server client credentials
2. Include Matrix access token in request body as `token` parameter
3. Verify `active` claim is `true` in introspection response
4. Extract `sub`, `client_id`, `scope`, and `exp` claims from response
5. Reject tokens where `active` is `false` with HTTP 401 Unauthorized
6. Validate `exp` claim has not expired

**Introspection Request:**

```
POST /oauth2/introspect HTTP/1.1
Host: mas.tween.example
Content-Type: application/x-www-form-urlencoded
Authorization: Basic base64(tmcp_server_001:client_secret)

token=<MATRIX_TOKEN>
```

**Introspection Response:**

```json
{
  "active": true,
  "scope": "urn:matrix:org.matrix.msc2967.client:api:*",
  "client_id": "element_web_001",
  "sub": "@alice:tween.example",
  "exp": 1735689900
}
```

#### 4.9.3 Replay Attack Prevention

- TEP tokens include `jti` (JWT ID) claim for deduplication
- TMCP Server MUST track used Matrix tokens within introspection cache window
- Matrix tokens MUST only be exchanged once for TEP

#### 4.9.4 Scope Escalation Prevention

- Requested scopes MUST be subset of mini-app registered scopes
- Pre-approved scopes MUST be explicitly defined in mini-app manifest
- Sensitive scopes ALWAYS require user consent

### 4.10 Matrix Integration

TMCP Server proxies Matrix operations using the user's MAS credentials. Servers MUST:

1. Extract `refresh_token_id` from TEP token's `mas_session` claim
2. Retrieve corresponding Matrix refresh token from token store
3. Obtain valid Matrix access token using refresh token at MAS endpoint
4. Add Authorization header with Bearer token to Matrix requests
5. Proxy request to Matrix homeserver endpoint
6. Return response from Matrix homeserver to mini-app

**Matrix Operation Proxying:**

The server MUST forward Matrix requests to the homeserver on behalf of authenticated users, preserving the user's MAS credentials and session context.

### 4.11 In-Chat Payment Architecture

TMCP implements in-chat payment notifications where payment events appear natively in Matrix rooms. This approach provides integrated payment events that appear as part of the conversation flow rather than external notifications.

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

**Payment Bot Registration Requirements:**

| Parameter | Required | Value/Description |
|-----------|-----------|-------------------|
| `id` | Yes | Same as TMCP Server AS registration |
| `url` | Yes | TMCP Server URL |
| `sender_localpart` | Yes | MUST be `_tmcp_payments` |
| `namespaces.users` | Yes | MUST include: `@_tmcp_payments:<hs>` pattern, exclusive |

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

Clients MUST render payment events as rich cards for in-chat payment notifications.

**Payment Receipt Card:**

Clients MUST render payment receipt cards with following elements:
- Payment status icon (completed: 💰, failed: ❌, pending: ⏳)
- Sender information (user_id, display_name, avatar_url)
- Transaction amount and currency
- Transaction note (if provided)
- Transaction ID and timestamp
- Action button to view full receipt details

**P2P Transfer Card:**

Clients MUST render P2P transfer cards with following elements:
- Transfer status icon (sent: 💸, failed: ❌, pending: ⏳)
- Recipient information (user_id, display_name, avatar_url)
- Transfer amount and currency
- Transfer note (if provided)
- Transaction ID and timestamp
- Status indicator (Completed/Pending/Failed)
- Action buttons (View Receipt, Send Again)

**Rendering Requirements:**

Cards MUST:
- Use consistent card styling across all payment types
- Display amounts with proper currency formatting
- Show timestamps in user's local timezone
- Support both light and dark theme rendering
- Be accessible with proper contrast ratios

**Client Implementation Reference:**

For reference implementation of payment event rendering, see **Appendix B: SDK Interface Definitions** which provides TypeScript `PaymentEventHandler` class with methods for rendering payment events.

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

   TMCP Server MUST verify wallet provider callback signatures before processing. Verification MUST:

   - Extract signature from `Authorization` header or `signature` field
   - Retrieve wallet provider's webhook secret from registry
   - Compute HMAC-SHA256 of payload using webhook secret
   - Compare computed signature with received signature using constant-time comparison
   - Reject callbacks with invalid signatures using HTTP 401 Unauthorized

   **Verification Process:**

   | Step | Action |
   |------|--------|
   | 1 | Extract payload and signature from callback |
   | 2 | Look up wallet provider's webhook secret |
   | 3 | Compute expected signature: HMAC-SHA256(secret, payload) |
   | 4 | Compare signatures using constant-time comparison |
   | 5 | Return verification result |

3. **Event Creation from Callback:**

   Upon successful signature verification, TMCP Server MUST create Matrix payment event:

   - Extract payment details from callback payload
   - Map wallet event type to Matrix event type (e.g., payment.completed → m.tween.payment.completed)
   - Construct event content with payment metadata
   - Send event to Matrix room as virtual payment bot user (@_tmcp_payments:tween.example)
   - Return event_id for tracking

**Event Content Structure:**

```json
{
  "type": "m.tween.payment.completed",
  "content": {
    "msgtype": "m.tween.payment",
    "payment_type": "completed",
    "visual": {
      "card_type": "payment_receipt",
      "icon": "payment_completed"
    },
    "transaction": {
      "txn_id": "txn_wallet_123",
      "amount": 15000.00,
      "currency": "USD"
    },
    "sender": {
      "user_id": "@alice:tween.example",
      "display_name": "Alice",
      "avatar_url": "mxc://tween.example/avatar123"
    },
    "recipient": {
      "miniapp_id": "ma_shop_001",
      "name": "Shopping Assistant"
    },
    "note": "Order #12345",
    "timestamp": "2025-12-18T14:30:00Z"
  }
}
```

#### 4.11.8 Payment Event Idempotency

To prevent duplicate payment events from wallet callbacks, TMCP Server MUST implement idempotency:

1. **Idempotency Key Generation**:
   - Extract `transaction_id` from callback payload
   - Generate idempotency key: `payment_event:{transaction_id}`

2. **Duplicate Detection**:
   - Check idempotency store for existing event_id using idempotency key
   - If event exists, return existing event_id without processing
   - If event does not exist, proceed with event creation

3. **Idempotency Storage**:
   - Store idempotency key with event_id in distributed cache
   - Set TTL of 24 hours (86400 seconds) for idempotency keys
   - Use Redis or equivalent distributed key-value store

4. **Processing Flow**:

   | Step | Action | Result |
   |------|--------|--------|
   | 1 | Receive wallet callback | |
   | 2 | Generate idempotency key | `payment_event:txn_123` |
   | 3 | Check for existing event | Found → Return existing |
   | 4 | Create payment event | |
   | 5 | Store idempotency key | `payment_event:txn_123` → `event_id` |
   | 6 | Return event_id | |

**Idempotency Response:**

```json
{
  "event_id": "$event_id_abc123",
  "idempotent": true,
  "transaction_id": "txn_wallet_123"
}
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

**Validation Requirements:**

TMCP Server MUST validate requested scopes against mini-app registration:

1. **Scope Registration Check**:
   - For each requested scope, verify it exists in mini-app's registered scopes
   - Reject scopes not registered for the mini-app

2. **Sensitivity Classification**:
   - Classify each scope as pre-approved or sensitive
   - Pre-approved scopes: Grant without user consent
   - Sensitive scopes: Require user approval unless previously granted

3. **User Consent Check**:
   - For sensitive scopes, check if user has previously approved
   - If not approved, mark as requiring consent
   - Return consent_needed error with list of required scopes

4. **Validation Result**:
   - Return `valid` array with approved scopes
   - Return `denied` array with rejected scopes and reasons
   - Reason codes: `not_registered`, `user_approval_required`

**Validation Response:**

```json
{
  "valid": ["user:read", "storage:write"],
  "denied": [
    {
      "scope": "wallet:pay",
      "reason": "user_approval_required"
    }
  ],
  "consent_required": ["wallet:pay"]
}
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

**Batch Wallet Status Resolution:**

For room membership scenarios, clients MAY use batch resolution:

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
  ],
  "room_id": "!chat123:tween.example"
}
```

**Response:**

```json
{
  "users": {
    "@alice:tween.example": {
      "has_wallet": true,
      "wallet_status": "active",
      "display_name": "Alice"
    },
    "@bob:tween.example": {
      "has_wallet": true,
      "wallet_status": "active",
      "display_name": "Bob"
    },
    "@charlie:tween.example": {
      "has_wallet": false,
      "wallet_status": "none",
      "invite_url": "https://tween.example/wallet/create?inviter=alice"
    }
  }
}
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

**Validation Requirements:**

1. **Feature Access Check**:
   - For P2P send operations, verify `p2p_send` feature is enabled
   - For high-value transactions, verify `high_value` feature is enabled
   - For international transfers, verify `international` feature is enabled
   - Return `P2P_SEND_NOT_ALLOWED` if feature not enabled

2. **Amount Limit Check**:
   - Compare transaction amount against user's transaction limit
   - Return `AMOUNT_EXCEEDS_LIMIT` if amount exceeds limit
   - Limit is determined by verification tier

3. **Daily Limit Check**:
   - Track daily transaction volume per user
   - Compare against daily limit for verification tier
   - Return `DAILY_LIMIT_EXCEEDED` if limit reached

4. **Validation Response**:

```json
{
  "eligible": true,
  "features": {
    "p2p_send": true,
    "high_value": false,
    "international": false
  },
  "limits": {
    "transaction_limit": 10000,
    "daily_limit": 50000,
    "monthly_limit": 200000
  },
  "current_usage": {
    "daily": 25000,
    "monthly": 75000
  }
}
```

**Error Responses:**

| Error | HTTP Status | Description |
|-------|-------------|-------------|
| `P2P_SEND_NOT_ALLOWED` | 403 | P2P send feature not enabled |
| `AMOUNT_EXCEEDS_LIMIT` | 400 | Transaction exceeds limit |
| `DAILY_LIMIT_EXCEEDED` | 429 | Daily limit reached |

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

TMCP Server MUST run scheduled jobs to process expired transfers. The processing MUST:

1. **Query Expired Transfers**: Find all transfers with status `pending_recipient_acceptance` where `created_at` is older than 24 hours
2. **Refund Processing**: For each expired transfer, refund the full amount to the sender's wallet
3. **Matrix Event Update**: Send a status update event to the original room indicating expiration and refund

**Expired Transfer Status Event:**
```json
{
  "type": "m.tween.wallet.p2p.status",
  "content": {
    "transfer_id": "p2p_abc123",
    "status": "expired",
    "expired_at": "2025-12-19T14:30:00Z",
    "refunded": true
  }
}
```

**Expiry Processing Requirements:**

| Step | Action | Result |
|------|--------|--------|
| 1 | Query pending transfers > 24h old | List of transfer_ids |
| 2 | Initiate refund for each | Refund transaction created |
| 3 | Update transfer status | Set to `expired` |
| 4 | Send Matrix event | Room receives status update |

**Error Handling:**
- Failed refunds MUST be logged and queued for retry
- Matrix event failures MUST NOT prevent refund processing
- Server MUST retry expiry processing at least 3 times before marking as failed

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

Clients MUST compute a cryptographic signature for payment authorization. The signature MUST be computed over the following concatenated string:

```
${payment_id}:${amount}:${currency}:${timestamp}
```

The signature MUST use the client's private key (hardware-backed or stored in secure enclave) and be Base64-encoded for transmission.

**Signature Computation Requirements:**

| Parameter | Format | Required |
|-----------|--------|----------|
| `payment_id` | String | Yes |
| `amount` | Decimal | Yes |
| `currency` | ISO 4217 code | Yes |
| `timestamp` | ISO 8601 | Yes |

**Algorithm Requirements:**
- MUST use SHA-256 for hash computation
- MUST use RS256 (RSA Signature with SHA-256) or ES256 (ECDSA with P-256 and SHA-256)
- Private key MUST be stored in hardware-backed keystore or secure enclave
- Timestamp MUST be within 5 minutes of server time

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

**Random Distribution Algorithm:**

The random distribution algorithm MUST allocate amounts such that each participant receives between 10% and 30% of the average per-recipient amount, except for the final recipient who receives the remaining balance. The algorithm MUST shuffle allocations to prevent order-based prediction.

**Random Distribution Requirements:**

1. **Calculate Average**: `average = total_amount / count`
2. **Per-Recipient Range**: Each amount MUST be between `0.10 * average` and `0.30 * average` (for first `count - 1` recipients)
3. **Final Recipient**: Receives all remaining amount after allocations
4. **Rounding**: All amounts MUST be rounded to 2 decimal places (cents)
5. **Shuffling**: The resulting distribution array MUST be shuffled before assignment

**Equal Distribution Algorithm:**

The equal distribution algorithm MUST divide the total amount evenly among all recipients, with any rounding adjustments applied to the first recipient.

**Equal Distribution Requirements:**

1. **Base Amount**: `base = round((total_amount / count), 2)`
2. **Distribution Array**: Create array of `count` entries with `base` value
3. **Rounding Adjustment**: Calculate `difference = total_amount - (base * count)` and add to first entry
4. **Result**: Each recipient receives `base`, first recipient receives `base + difference`

**Algorithm Selection:**

| Distribution Type | Characteristics | Use Case |
|-------------------|-----------------|----------|
| `random` | Variable amounts, gamified | Social gifting, celebrations |
| `equal` | Fixed amounts, predictable | Split bills, fair division |

**Configuration Parameters:**

| Parameter | Type | Default | Range |
|-----------|------|---------|-------|
| `min_percentage` | Number | 10% | 5-20% |
| `max_percentage` | Number | 30% | 25-50% |
| `round_to_cents` | Boolean | true | - |

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

**Race Condition Prevention:**

Multiple users opening gifts simultaneously MUST NOT cause inconsistent state. Implementations MUST use database-level locking and atomic operations to ensure consistency.

**Atomicity Requirements:**

1. **Row Locking**: The gift record MUST be locked using `SELECT FOR UPDATE` (or equivalent) before checking `remaining_count`
2. **Status Check**: Within the locked transaction, validate `remaining_count > 0`
3. **Atomic Update**: Decrement `remaining_count` and insert opening record in same transaction
4. **Concurrency Response**: Return HTTP 409 CONFLICT if gift is fully opened during request processing

**Transaction Flow:**

| Step | Action | Lock Scope |
|------|--------|------------|
| 1 | BEGIN transaction | - |
| 2 | SELECT gift FOR UPDATE | Exclusive row lock |
| 3 | Validate remaining_count > 0 | Within lock |
| 4 | Calculate allocation | - |
| 5 | UPDATE remaining_count | Within lock |
| 6 | INSERT opening record | Within lock |
| 7 | COMMIT | Lock released |

**Error Responses:**

HTTP 409 CONFLICT:
```json
{
  "error": {
    "code": "GIFT_EMPTY",
    "message": "Gift has already been fully opened"
  }
}
```

HTTP 409 CONFLICT (duplicate opening):
```json
{
  "error": {
    "code": "ALREADY_OPENED",
    "message": "You have already opened this gift"
  }
}
```

**Implementation Requirements:**

- Database transactions MUST have isolation level at least READ COMMITTED
- Lock timeout SHOULD be configured to prevent indefinite blocking (recommended: 5 seconds)
- Server MUST detect and reject duplicate opening attempts by same user
- Failed transactions MUST be rolled back completely

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

**Data Injection Security:**

Clients MUST NOT inject sensitive data (tokens, credentials) into WebView JavaScript context. Tokens exposed to JavaScript can be extracted by malicious scripts.

**Secure Communication Requirements:**

| Pattern | Requirement | Rationale |
|---------|-------------|-----------|
| Token Injection | MUST NOT inject tokens via JavaScript | Prevents extraction by malicious scripts |
| postMessage | MUST use for initialization messages | Sandboxed communication channel |
| Message Content | MUST NOT include tokens or secrets | Reduces exposure risk |
| Target Origin | SHOULD use specific origin ('*' only when necessary) | Prevents cross-origin leaks |

**Secure Initialization Message Format:**
```json
{
  "type": "TMCP_INIT_SUCCESS",
  "user_id": "@alice:tween.example"
}
```

**Anti-Patterns to Avoid:**
- `window.tepToken = '<token>'` - Exposes token to JavaScript
- `loadUrl("javascript:...")` with tokens - Token visible in URL/history
- LocalStorage for tokens - Accessible via JavaScript

**Required Security Measures:**
- All sensitive data communication MUST use postMessage with origin validation
- Tokens MUST remain in native code/secure storage
- Client MUST validate message origin before processing

#### 10.4.6 Certificate Pinning

**Overview:**

For high-security mini-apps, clients SHOULD implement certificate pinning to prevent man-in-the-middle attacks. Certificate pinning binds the TLS connection to a specific certificate or public key.

**Certificate Pinning Requirements:**

| Requirement | Description |
|-------------|-------------|
| Pin Format | SHA-256 hash of certificate or public key |
| Pin Storage | Pins MUST be embedded in application binary (not runtime configuration) |
| Backup Pins | MUST include backup pins for certificate rotation |
| Pin Validation | Client MUST validate pins on each TLS handshake |
| Fail Mode | Connection MUST fail if pin validation fails |

**Pin Configuration:**

```
Domain: tmcp.example.com
Pin: sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
Backup: sha256/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=
```

**Implementation Requirements:**
- Pins MUST use SHA-256 hash algorithm
- Client MUST validate both primary and backup pins
- Certificate rotation MUST be coordinated with pin updates
- Failed pin validation MUST terminate the connection
- Pins SHOULD be rotated at least annually

**Fallback Behavior:**
- If pin validation fails, client SHOULD alert user
- User option to bypass MUST be disabled by default
- Bypass decisions MUST NOT be persisted across sessions

#### 10.4.7 WebView Lifecycle Management

**Overview:**

Sensitive data MUST be cleared when WebView lifecycle events occur to prevent data exposure. Different lifecycle events require different levels of cleanup.

**Lifecycle Cleanup Requirements:**

| Lifecycle Event | Actions Required |
|-----------------|------------------|
| `onPause` | Clear cache, clear form data |
| `onStop` | Clear history (if sensitive app) |
| `onDestroy` | Clear all data, destroy WebView instance |

**Cleanup Operations:**

| Operation | Description | Required On |
|-----------|-------------|-------------|
| `clearCache(true)` | Clear HTTP cache | All pauses |
| `clearFormData()` | Clear autocomplete data | All pauses |
| `clearHistory()` | Clear navigation history | Sensitive apps on stop |
| `removeAllViews()` | Remove child views | Destroy |
| `destroy()` | Destroy WebView instance | Destroy |

**Conditional Cleanup:**

Applications handling payments or sensitive operations MUST clear history on stop in addition to standard pause cleanup.

**Security Requirements:**
- Cache MUST be cleared on every pause
- Form data MUST be cleared on every pause
- History clearing REQUIRED for payment-handling apps
- All cleanup MUST complete before lifecycle callback returns
- Destroy MUST be called to release native resources

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

**Token Bucket Algorithm:**

The rate limiter MUST implement token bucket algorithm with the following behavioral requirements:

**Bucket Initialization:**

| Parameter | Description | Default |
|-----------|-------------|---------|
| `capacity` | Base token count per window | 100 |
| `burst` | Additional tokens for burst allowance | 0 |
| `rate` | Tokens refilled per second | 1 |
| `tokens` | Current token count | capacity + burst |
| `last_update` | Timestamp of last refill | current_time |

**Token Refill Process:**

1. **Calculate Elapsed Time**: Compute `elapsed = current_time - last_update`
2. **Add Tokens**: `tokens = min(capacity + burst, tokens + (elapsed * rate))`
3. **Update Timestamp**: Set `last_update = current_time`

**Request Validation:**

| Condition | Action | Result |
|-----------|--------|--------|
| `tokens >= 1` | Consume 1 token | Allow request |
| `tokens < 1` | Reject request | Calculate retry delay |

**Retry Delay Calculation:**

```
retry_after = (1 - tokens) / rate
```

**Rate Limit Response Headers:**

```http
HTTP/1.1 200 OK
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1735689600

HTTP/1.1 429 Too Many Requests
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1735689600
Retry-After: 60
```

**Algorithm Requirements:**
- Each client/key MUST have independent bucket state
- Token refill MUST be calculated on each request
- Tokens MUST be capped at `capacity + burst`
- Server MUST return remaining tokens in response header
- Server MUST return reset timestamp in response header

#### 11.4.3 Distributed Rate Limiting

For multi-instance TMCP Server deployments, use Redis-based sliding window algorithm:

1. **Redis Sorted Sets**:
   - Use Redis sorted sets with timestamp as score
   - Key format: `{key_prefix}:{identifier}`

2. **Request Counting**:
   - On each request, remove entries older than `window` seconds
   - Count remaining entries in current window
   - If count < rate, add new entry with current timestamp

3. **Token Counting**:
   - Use Redis `ZREMRANGEBYSCORE` to remove old entries
   - Use `ZCARD` to count requests in window
   - Use `ZADD` to add new request timestamp
   - Use `EXPIRE` to set key TTL

4. **Distributed Validation**:
   - If count < rate, allow request and return remaining quota
   - If count >= rate, reject request and calculate `retry_after`
   - Use `ZRANGE` to find oldest request for retry calculation

**Redis Operations:**

| Operation | Redis Command | Purpose |
|-----------|---------------|---------|
| Remove old entries | `ZREMRANGEBYSCORE` | Cleanup expired requests |
| Count requests | `ZCARD` | Count in current window |
| Add request | `ZADD` | Record new request |
| Set expiry | `EXPIRE` | Auto-cleanup key |
| Get oldest | `ZRANGE` | Calculate retry time |

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
| `CONSENT_REQUIRED` | 403 | User must approve sensitive scopes | No |
| `INVALID_SCOPE` | 400 | Requested scope not registered for mini-app | No |

### 12.3 Authentication Error Responses

**Invalid Matrix Token:**

```http
HTTP/1.1 401 Unauthorized
Content-Type: application/json

{
  "error": "invalid_grant",
  "error_description": "Matrix token is invalid or expired"
}
```

**Consent Required:**

```http
HTTP/1.1 403 Forbidden
Content-Type: application/json

{
  "error": "consent_required",
  "error_description": "User must approve sensitive scopes",
  "consent_required_scopes": ["wallet:pay"],
  "pre_approved_scopes": ["user:read", "storage:write"],
  "consent_ui_endpoint": "/oauth2/consent?session=xyz"
}
```

**Scope Not Registered:**

```http
HTTP/1.1 400 Bad Request
Content-Type: application/json

{
  "error": "invalid_scope",
  "error_description": "Requested scope 'wallet:admin' not registered for this mini-app"
}
```

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

**[RFC7662]** Richer, J., Ed., "OAuth 2.0 Token Introspection", RFC 7662, September 2015.

**[RFC7009]** Lodderstedt, T., Ed., "OAuth 2.0 Token Revocation", RFC 7009, August 2015.

**[RFC8628]** Jones, M., Bradley, J., and N. Sakimura, "OAuth 2.0 Device Authorization Grant", RFC 8628, August 2019.

**[RFC8693]** Jones, M., Bradley, J., and N. Sakimura, "OAuth 2.0 Token Exchange", RFC 8693, August 2019.

**[RFC4627]** Crockford, D., "The application/json Media Type for JavaScript Object Notation (JSON)", RFC 4627, July 2006.

**[Matrix-Spec]** The Matrix.org Foundation, "Matrix Specification v1.15", https://spec.matrix.org/v1.15/

**[Matrix-AS]** The Matrix.org Foundation, "Matrix Application Service API", https://spec.matrix.org/v1.15/application-service-api/

**[MSC3861]** The Matrix.org Foundation, "Matrix Authentication Service (MAS)", https://github.com/matrix-org/matrix-spec-proposals/pull/3861

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

TMCP Server MUST be registered as a confidential client in MAS with:

| Parameter | Required | Value/Description |
|-----------|-----------|-------------------|
| `client_auth_method` | Yes | `client_secret_post` |
| `grant_types` | Yes | MUST include: `authorization_code`, `device_code`, `refresh_token`, `urn:ietf:params:oauth:grant-type:reverse_1` |
| `scope` | Yes | MUST include: `openid`, `urn:matrix:org.matrix.msc2967.client:api:*`, `urn:synapse:admin:*` |

**Mini-App Client Registration:**

Each mini-app MUST be registered in MAS with:

| Parameter | Required | Value/Description |
|-----------|-----------|-------------------|
| `client_id` | Yes | Unique identifier for mini-app |
| `client_auth_method` | Yes | `client_secret_post` |
| `redirect_uris` | Yes | Array of valid callback URLs |
| `grant_types` | Yes | MUST include: `authorization_code`, `device_code`, `refresh_token` |
| `scope` | Yes | MUST include: `openid`, `urn:matrix:org.matrix.msc2967.client:api:*` |

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

**Protocol Flow Sequence:**

1. **Device Authorization Grant** - Mini-app obtains Matrix access token:
   - Mini-app initiates Device Authorization Grant (RFC 8628)
   - User completes authorization on separate device/browser
   - MAS issues access token and refresh token

2. **Matrix Session Delegation** - Mini-app exchanges Matrix token for TEP:
   - Mini-app sends Matrix access token to TMCP Server via Token Exchange (RFC 8693)
   - TMCP Server validates Matrix token with MAS introspection (RFC 7662)
   - TMCP Server issues TEP token (JWT) with mini-app authorization claims
   - TEP token includes wallet_id and scopes

3. **Payment Request** - Mini-app initiates payment:
   - Mini-app calls TMCP Server payment endpoint with TEP token
   - Request includes transaction details (amount, recipient, note)
   - TMCP Server validates TEP token and requested scopes

4. **Payment Authorization** - User authorizes payment:
   - Client displays payment confirmation UI
   - User provides biometric authentication or PIN
   - Client signs payment request with hardware key
   - Signed payment request sent to TMCP Server

5. **Payment Processing** - TMCP Server coordinates payment:
   - TMCP Server validates signature and transaction details
   - TMCP Server forwards payment request to Wallet Service
   - Wallet Service executes transfer or creates transaction record
   - Wallet Service returns payment result to TMCP Server

6. **Payment Confirmation** - TMCP Server notifies client and Matrix:
   - TMCP Server creates Matrix payment event (m.tween.payment.completed)
   - TMCP Server sends event to Matrix room via Application Service
   - TMCP Server sends webhook notification to mini-app

7. **Payment Receipt in Chat** - Client renders payment event:
   - Matrix room receives payment event from virtual payment bot
   - Client renders rich payment card in chat interface
   - Payment card displays transaction details, amount, and status
   - User can view full receipt details or initiate additional actions

**Protocol Sequence Diagram:**

```
User A                            User B
  │                                    │
  │ 1. Device Auth                  │
  ▼                                    ▼
┌────────────────┐              ┌────────────────┐
│ Mini-app      │              │   Mini-app      │
│              │              │   │              │
└──────┬───────┘              └──────┬───────────┘
       │                             │
       │ Token Exchange                 │ Token Exchange
       ▼                             ▼
┌────────────────┐              ┌────────────────┐
│ TMCP Server  │              │   TMCP Server  │
│              │              │   │              │
└──────┬───────┘              └──────┬───────────┘
       │                             │
       │ Payment Coordination           │ Payment Coordination
       ▼                             ▼
┌────────────────┐              ┌────────────────┐
│ Wallet Service │              │   Wallet Service │
│              │              │   │              │
└──────────────┘              └──────────────┘
       │                             │
       │ Matrix Payment Events         │ Matrix Payment Events
       ▼                             ▼
┌─────────────────────────────────────────────────────┐
│                 Matrix Chat Room                  │
│  Payment bot sends m.tween.payment.completed event  │
└─────────────────────────────────────────────────────┘
```

**Key Protocol Elements:**

| Step | Protocol Element | Specification Reference |
|-------|------------------|------------------------|
| 1 | Device Authorization Grant | RFC 8628 |
| 2 | Matrix Session Delegation | RFC 8693, RFC 7662 |
| 3 | TEP Token Issuance | RFC 7519 |
| 4 | Payment Authorization | Section 7.2 |
| 5 | Payment Processing | Section 7.5 |
| 6 | Payment Events | Section 8.1 |
| 7 | Application Service | Matrix AS API |

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

**End of TMCP-001**