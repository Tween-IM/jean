#!/bin/bash
# TMCP Server Quick Deployment Script
# Run this on your TMCP server after infrastructure is ready

set -e

echo "=== TMCP Server Deployment Script ==="
echo

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v ruby &> /dev/null; then
    echo "❌ Ruby not found. Please install Ruby 3.4.4"
    exit 1
fi

if ! command -v bundle &> /dev/null; then
    echo "❌ Bundler not found. Please install Bundler"
    exit 1
fi

if ! command -v psql &> /dev/null; then
    echo "❌ PostgreSQL client not found"
    exit 1
fi

echo "✅ Prerequisites OK"

# Clone/update repository
echo
echo "Setting up application directory..."
APP_DIR="/opt/tmcp"
REPO_URL="https://github.com/mona-chen/jean.git"

if [ -d "$APP_DIR" ]; then
    echo "Application directory exists, updating..."
    cd "$APP_DIR"
    git pull origin main
else
    echo "Cloning repository..."
    git clone "$REPO_URL" "$APP_DIR"
    cd "$APP_DIR"
fi

# Install dependencies
echo
echo "Installing Ruby dependencies..."
bundle install --deployment --without development test

# Setup database
echo
echo "Setting up database..."
if [ -z "$DATABASE_URL" ]; then
    echo "❌ DATABASE_URL environment variable not set"
    echo "Please set DATABASE_URL before running this script"
    exit 1
fi

bundle exec rails db:create db:migrate db:seed RAILS_ENV=production
# db:seed now loads official mini-apps from config/mini_apps.yml and approves them

# Precompile assets
echo
echo "Precompiling assets..."
bundle exec rails assets:precompile RAILS_ENV=production

# Setup systemd service
echo
echo "Setting up systemd service..."
cp deploy/tmcp.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable tmcp

echo
echo "=== Deployment Complete ==="
echo
echo "Next steps:"
echo "1. Configure your .env file with production values"
echo "2. Configure Nginx with SSL certificates"
echo "3. Start the service: systemctl start tmcp"
echo "4. Test the deployment"
echo
echo "For detailed instructions, see DEPLOYMENT.md"