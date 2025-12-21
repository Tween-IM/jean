# AGENTS.md - TMCP Server Development Guidelines

## Documentation Research
- **Source of Truth**: PROTO.md only - all implementation must be 110% compliant
- **Research Existing Docs**: Review architectural documents for compliance before implementation
- **Use Compliant Docs**: When existing docs are 100% protocol-compliant, use them as implementation guides
- **Reject Non-Compliant**: Do not implement features or patterns from docs that extend beyond PROTO.md scope
- **Ask for Clarification**: If unsure about protocol compliance, ask before proceeding

## Build/Test Commands
```bash
# Install dependencies
bundle install

# Setup database
rails db:setup

# Run all tests
rails test

# Run single test file
rails test test/models/user_test.rb

# Run specific test by pattern
rails test -n "/oauth/"

# Run service tests
rails test test/services/

# Run controller tests
rails test test/controllers/

# Run integration tests
rails test test/integration/

# Run system tests
rails test:system

# Lint code (Rubocop)
bundle exec rubocop

# Format code (RuboCop auto-fix)
bundle exec rubocop -a

# Security audit
bundle exec bundler-audit

# Start server
rails server

# Start server with environment
rails server -e production
```

## Rails Code Style Guidelines

### Ruby/Rails Conventions
- Follow Ruby Style Guide and Rails conventions
- Use 2-space indentation, no tabs
- Line length: 120 characters maximum
- Use snake_case for methods, variables, files
- Use CamelCase for classes, modules
- Use SCREAMING_SNAKE_CASE for constants
- Use meaningful, descriptive names

### Models (ActiveRecord)
- Use Rails validations for data integrity
- Implement proper associations and scopes
- Use enums for status fields
- Add database indexes for performance
- Include comprehensive model specs

### Controllers
- Keep controllers thin, extract logic to services
- Use strong parameters for mass assignment
- Implement proper error handling with rescue_from
- Return appropriate HTTP status codes
- Use Jbuilder or serializers for JSON responses

### Services
- Extract complex business logic to service objects
- Follow single responsibility principle
- Use dependency injection where appropriate
- Write comprehensive service specs

### Error Handling
- Use custom error classes in app/errors/
- Implement rescue_from in ApplicationController
- Log errors with context using Rails.logger
- Return structured error responses per TMCP protocol
- Never expose internal errors to clients

### Security (TMCP Protocol Compliant)
- Use strong parameters validation
- Implement OAuth 2.0 + PKCE as specified
- Use TEP JWT tokens for mini-app auth
- Rate limiting on all endpoints per protocol
- HMAC-SHA256 for webhook signatures
- Parameterized queries only (ActiveRecord handles this)
- Never log sensitive data (passwords, tokens, payment details)

### Testing (Rails Minitest)
- Unit tests for models, services, utilities
- Integration tests for API endpoints
- System tests for critical user journeys
- Mock external dependencies (Wallet Service, Matrix)
- Use fixtures for consistent test data
- Aim for comprehensive coverage of protocol features

### Database
- Use PostgreSQL with proper indexing
- Implement database constraints
- Use migrations for schema changes
- Follow Rails naming conventions
- Use UUIDs for primary keys where appropriate

### API Design (TMCP Protocol Compliant)
- RESTful endpoints following Rails conventions
- JSON responses matching protocol specifications
- Proper HTTP status codes
- Idempotency keys for payments/transfers
- Request/response validation with dry-validation

### Protocol Compliance
- **Source of Truth**: PROTO.md only
- Implement only features explicitly mentioned in protocol
- No overreaching or feature additions
- 100% compliance with OAuth 2.0 + PKCE flow
- Exact Matrix event formats and types
- Precise payment state machines and flows
- Wallet integration as specified in Section 6

## API Documentation

### Matrix Application Service Endpoints

#### Transaction Processing
```
PUT /_matrix/app/v1/transactions/:txn_id
```
Handles incoming Matrix events from homeserver. Processes room messages, member events, and TMCP-related commands.

#### User Queries
```
GET /_matrix/app/v1/users/:user_id
```
Queries user existence for room membership validation. Returns 200 if user exists, 404 if not.

#### Room Queries
```
GET /_matrix/app/v1/rooms/:room_alias
```
Queries room alias existence. Returns 200 for TMCP-prefixed rooms.

#### Health Check
```
GET /_matrix/app/v1/ping
```
Application Service health check endpoint.

#### Third-Party Protocols
```
GET /_matrix/app/v1/thirdparty/location
GET /_matrix/app/v1/thirdparty/user
GET /_matrix/app/v1/thirdparty/location/:protocol
GET /_matrix/app/v1/thirdparty/user/:protocol
```
Third-party protocol integration endpoints (reserved for future use).

### TMCP API Endpoints

#### OAuth 2.0 Endpoints
```
GET  /api/v1/oauth/authorize
POST /api/v1/oauth/token
```
OAuth 2.0 + PKCE authorization flow for mini-app authentication.

#### Wallet Endpoints
```
GET  /api/v1/wallet/balance
GET  /api/v1/wallet/transactions
POST /api/v1/wallet/p2p/initiate
POST /api/v1/wallet/p2p/:transfer_id/accept
POST /api/v1/wallet/p2p/:transfer_id/reject
GET  /api/v1/wallet/resolve/:user_id
```
Wallet balance, transaction history, P2P transfers, and user resolution.

#### Payment Endpoints
```
POST /api/v1/payments/request
POST /api/v1/payments/:payment_id/authorize
POST /api/v1/payments/:payment_id/refund
POST /api/v1/payments/:payment_id/mfa/challenge
POST /api/v1/payments/:payment_id/mfa/verify
```
Mini-app payment processing with MFA support.

#### Gift Endpoints
```
POST /api/v1/gifts/create
POST /api/v1/gifts/:gift_id/open
```
Group gift creation and opening.

#### Storage Endpoints
```
GET    /api/v1/storage
POST   /api/v1/storage
GET    /api/v1/storage/:key
PUT    /api/v1/storage/:key
DELETE /api/v1/storage/:key
POST   /api/v1/storage/batch
GET    /api/v1/storage/info
```
Mini-app key-value storage with batch operations.

### Environment Variables

#### Required for Production
- `TMCP_PRIVATE_KEY`: RSA private key for JWT signing
- `MATRIX_API_URL`: Matrix homeserver API URL
- `MATRIX_HS_TOKEN`: Homeserver token for AS registration
- `MATRIX_ACCESS_TOKEN`: Access token for event publishing
- `SECRET_KEY_BASE`: Rails secret key base
- `POSTGRES_PASSWORD`: Database password

#### Optional
- `TMCP_JWT_ISSUER`: JWT issuer URL (default: https://tmcp.example.com)
- `FORCE_SSL`: Enable SSL enforcement (default: false)
- `ALLOWED_ORIGINS`: CORS allowed origins
- `REDIS_URL`: Redis connection URL for caching

### Matrix Event Types

TMCP defines custom Matrix event types in the `m.tween.*` namespace:

- `m.tween.payment.completed`: Payment completion notifications
- `m.tween.wallet.p2p`: P2P transfer events
- `m.tween.wallet.p2p.status`: Transfer status updates
- `m.tween.gift`: Group gift creation
- `m.tween.gift.opened`: Gift opening events
- `m.tween.miniapp.launch`: Mini-app launch events
- `m.room.tween.authorization`: Authorization state changes