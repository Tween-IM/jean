# Wallet Service Integration Setup

## Overview
The TMCP server has been updated to integrate with the real Tween Pay wallet service instead of using mock implementations. The wallet service provides:

- Real balance management
- Transaction processing
- P2P transfers
- Payment authorization
- User verification

## Configuration

### Environment Variables
Add these to your `.env` file:

```bash
# Wallet Service API Configuration
WALLET_API_BASE_URL=http://localhost:3001  # For local tween-pay service
WALLET_API_KEY=your_api_key_here           # If authentication is required
WALLET_API_TIMEOUT=30                      # Request timeout in seconds
```

### Production Setup
For production deployment:

```bash
WALLET_API_BASE_URL=https://your-wallet-service.com
WALLET_API_KEY=production_api_key
```

## Running the Wallet Service Locally

1. **Navigate to the tween-pay directory:**
   ```bash
   cd /config/workspace/tween-pay
   ```

2. **Set up environment:**
   ```bash
   cp .env.example .env
   # Edit .env with your database and API configurations
   ```

3. **Start the services:**
   ```bash
   docker-compose up -d
   ```

4. **Run database migrations:**
   ```bash
   docker-compose exec app rails db:create db:migrate db:seed
   ```

5. **Start the Rails server:**
   ```bash
   docker-compose exec app rails server -p 3001
   ```

## API Endpoints Integration

The wallet service integrates with these TMCP endpoints:

### Wallet Balance
- **TMCP:** `GET /api/v1/wallet/balance`
- **Wallet Service:** `GET /api/v1/tmcp/wallets/balance`

### Transaction History
- **TMCP:** `GET /api/v1/wallet/transactions`
- **Wallet Service:** `GET /api/v1/tmcp/wallet/transactions`

### P2P Transfers
- **TMCP:** `POST /api/v1/wallet/p2p/initiate`
- **Wallet Service:** `POST /api/v1/tmcp/transfers/p2p/initiate`

### Payment Requests
- **TMCP:** `POST /api/v1/payments/request`
- **Wallet Service:** `POST /api/v1/tmcp/payments/request`

## Authentication

The wallet service uses TEP tokens for authentication. The integration automatically:

1. Extracts the Matrix user ID from TEP tokens
2. Maps it to internal user IDs in the wallet service
3. Includes proper headers for user identification

## Error Handling

The integration includes:
- Circuit breaker pattern for resilience
- Proper error mapping from wallet service to TMCP format
- Fallback handling for unavailable services
- Comprehensive logging

## Testing

To test the integration:

1. **Start both services:**
   ```bash
   # TMCP server (port 3000)
   rails server -p 3000

   # Wallet service (port 3001)
   cd ../tween-pay && rails server -p 3001
   ```

2. **Test wallet balance:**
   ```bash
   curl -X GET http://localhost:3000/api/v1/wallet/balance \
     -H "Authorization: Bearer {TEP_TOKEN}"
   ```

## Migration from Mock to Real Service

The `WalletService` class has been completely rewritten to:
- Remove all mock implementations
- Add HTTP client integration with the real wallet service
- Maintain PROTO.md compliance
- Include proper error handling and circuit breakers

All existing TMCP endpoints continue to work without changes to the API contract.