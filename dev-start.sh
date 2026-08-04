#!/bin/bash
# Development Environment Setup Script
# Starts MAS and TMCP Server for local development/testing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================"
echo "TMCP Server Development Environment"
echo "========================================"
echo ""
echo "This will start:"
echo "  - PostgreSQL database"
echo "  - Redis cache"
echo "  - Matrix Authentication Service (MAS)"
echo "  - TMCP Server application"
echo ""
echo "After starting, access:"
echo "  - TMCP Server: http://localhost:3000"
echo "  - MAS Admin:   http://localhost:8080/api/admin/v1"
echo "  - MAS OpenID:  http://localhost:8080/.well-known/openid-configuration"
echo ""
echo "========================================"

# Check if secrets exist
if [ ! -f "secrets/mas_client_secret.txt" ]; then
    echo "Creating MAS client secret..."
    openssl rand -base64 32 > secrets/mas_client_secret.txt
    chmod 600 secrets/mas_client_secret.txt
fi

if [ ! -f "secrets/tmcp_private_key.txt" ]; then
    echo "Creating TMCP private key..."
    openssl genrsa -out secrets/tmcp_private_key.txt 2048 2>/dev/null
    chmod 600 secrets/tmcp_private_key.txt
fi

if [ ! -f "secrets/phone_hash_pepper.txt" ]; then
    echo "Creating phone hash pepper..."
    openssl rand -base64 32 | tr -d '\n' > secrets/phone_hash_pepper.txt
    chmod 600 secrets/phone_hash_pepper.txt
fi

# Start services
echo ""
echo "Starting services..."
docker compose -f docker-compose.dev.yml up -d

echo ""
echo "Waiting for services to be healthy..."

# Wait for MAS to be ready
echo "Waiting for MAS..."
for i in {1..30}; do
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        echo "MAS is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "ERROR: MAS failed to start within 30 seconds"
        docker compose -f docker-compose.dev.yml logs mas
        exit 1
    fi
    sleep 1
done

# Wait for TMCP Server to be ready
echo "Waiting for TMCP Server..."
for i in {1..30}; do
    if curl -s http://localhost:3000/health > /dev/null 2>&1 || curl -s http://localhost:3000 > /dev/null 2>&1; then
        echo "TMCP Server is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "WARNING: TMCP Server may not be ready yet"
        break
    fi
    sleep 1
done

echo ""
echo "========================================"
echo "Development Environment Started!"
echo "========================================"
echo ""
echo "Useful commands:"
echo "  View logs:       docker compose -f docker-compose.dev.yml logs -f"
echo "  Stop services:   docker compose -f docker-compose.dev.yml down"
echo "  Run tests:       bundle exec rails test"
echo "  Open console:    bundle exec rails console"
echo ""
echo "MAS OpenID Configuration:"
curl -s http://localhost:8080/.well-known/openid-configuration | head -20
echo ""
echo "========================================"
