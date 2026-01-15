#!/bin/bash
# Setup script for TMCP Server secrets
# Run this to generate development keys and create secrets directory

set -e

SECRETS_DIR="$(dirname "$0")/secrets"
KEY_FILE="$SECRETS_DIR/tmcp_private_key.txt"
MAS_SECRET_FILE="$SECRETS_DIR/mas_client_secret.txt"

echo "🔐 TMCP Server Secrets Setup"
echo "============================"

# Create secrets directory
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

# Generate TMCP private key if not exists
if [ ! -f "$KEY_FILE" ]; then
    echo "📝 Generating TMCP RSA private key..."
    openssl genrsa -out "$KEY_FILE" 2048
    chmod 600 "$KEY_FILE"
    echo "✅ Private key generated: $KEY_FILE"
else
    echo "✅ Private key already exists: $KEY_FILE"
fi

# Create MAS client secret placeholder if not exists
if [ ! -f "$MAS_SECRET_FILE" ]; then
    echo "⚠️  MAS client secret not found at $MAS_SECRET_FILE"
    echo "   Get this from your MAS admin console and save it to this file"
    echo "   Or run: echo 'your_mas_secret' > $MAS_SECRET_FILE"
    echo ""
    # Create placeholder with instructions
    cat > "$MAS_SECRET_FILE" << 'EOF'
# IMPORTANT: Replace this with your actual MAS client secret
# Get this from your Matrix Authentication Service (MAS) admin console
# 
# To get your MAS client secret:
# 1. Access MAS admin console (e.g., https://mas.tween.example/admin)
# 2. Go to Clients > tmcp-server
# 3. Copy the client secret
# 4. Paste it here (remove this comment)
EOF
    chmod 600 "$MAS_SECRET_FILE"
    echo "✅ Created MAS secret placeholder: $MAS_SECRET_FILE"
else
    echo "✅ MAS secret file exists: $MAS_SECRET_FILE"
fi

# Create .env from example if not exists
if [ ! -f ".env" ]; then
    echo "📝 Creating .env from .env.example..."
    cp .env.example .env
    echo "✅ Created .env - please edit with your actual values"
else
    echo "✅ .env already exists"

    # Remind about MAS secret
    if grep -q "MAS_CLIENT_SECRET=$" ".env" 2>/dev/null; then
        echo ""
        echo "⚠️  WARNING: MAS_CLIENT_SECRET is empty in .env"
        echo "   Update $MAS_SECRET_FILE with your actual MAS client secret"
    fi
fi

echo ""
echo "📋 Next steps:"
echo "   1. Edit .env with your actual configuration values"
echo "   2. Update $MAS_SECRET_FILE with your real MAS client secret"
echo "   3. Run: docker-compose up -d"
echo ""
echo "🔒 Security reminders:"
echo "   - Never commit secrets to version control"
echo "   - Add secrets/ to .gitignore"
echo   "   - Use Docker secrets or external secret management in production"
