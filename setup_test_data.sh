#!/bin/bash
# Setup test data for API testing

echo "Setting up test data..."

# Check if Doorkeeper application exists
APP_EXISTS=$(curl -s -X GET "http://localhost:3000/oauth/applications.json" \
  -H "Content-Type: application/json" | jq -r '.[] | select(.uid=="ma_test_001") | .uid // empty')

if [ "$APP_EXISTS" != "ma_test_001" ]; then
    echo "Creating Doorkeeper application for ma_test_001..."
    # Create Doorkeeper application via Rails runner
    rails runner "
      app = Doorkeeper::Application.create!(
        name: 'Test Mini-App',
        uid: 'ma_test_001',
        secret: 'test_secret_123',
        redirect_uri: 'http://localhost:3000/callback',
        scopes: 'user:read wallet:balance storage:write',
        confidential: false
      )
      puts 'Created Doorkeeper app: #{app.uid}'
    "
else
    echo "Doorkeeper application ma_test_001 already exists"
fi

# Create MiniApp
rails runner "
  miniapp = MiniApp.find_or_create_by(app_id: 'ma_test_001') do |m|
    m.name = 'Test Mini-App'
    m.version = '1.0.0'
    m.classification = 'community'
    m.status = 'active'
    m.client_type = 'public'
    m.manifest = {
      'scopes' => ['user:read', 'wallet:balance', 'storage:write'],
      'permissions' => {'storage' => 'read_write', 'user' => 'read_basic'}
    }.to_json
  end
  puts 'Created/Found MiniApp: #{miniapp.app_id} (#{miniapp.name})'
"

echo "Test data setup complete!"
echo ""
echo "Test credentials:"
echo "  client_id: ma_test_001"
echo "  Matrix access token: mct_sb8qD8zPPZWp05qrCg3Xv90cUWtNKh_0QGYVE"
echo ""
