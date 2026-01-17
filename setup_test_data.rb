#!/usr/bin/env ruby

# Setup test data for API testing

puts "Setting up test data..."

# Create Doorkeeper application
app = Doorkeeper::Application.find_by(uid: 'ma_test_001')
if app.nil?
  app = Doorkeeper::Application.create!(
    name: 'Test Mini-App',
    uid: 'ma_test_001',
    secret: 'test_secret_123',
    redirect_uri: 'http://localhost:3000/callback',
    scopes: 'user:read wallet:balance storage:write',
    confidential: false
  )
  puts "Created Doorkeeper app: #{app.uid}"
else
  puts "Doorkeeper application #{app.uid} already exists"
end

# Create MiniApp
miniapp = MiniApp.find_by(app_id: 'ma_test_001')
if miniapp.nil?
  miniapp = MiniApp.create!(
    app_id: 'ma_test_001',
    name: 'Test Mini-App',
    version: '1.0.0',
    classification: 'community',
    status: 'active',
    client_type: 'public',
    manifest: {
      'scopes' => [ 'user:read', 'wallet:balance', 'storage:write' ],
      'permissions' => { 'storage' => 'read_write', 'user' => 'read_basic' }
    }.to_json
  )
  puts "Created MiniApp: #{miniapp.app_id} (#{miniapp.name})"
else
  puts "MiniApp #{miniapp.app_id} already exists"
end

puts ""
puts "Test data setup complete!"
puts ""
puts "Test credentials:"
puts "  client_id: ma_test_001"
puts "  Matrix access token: mct_sb8qD8zPPZWp05qrCg3Xv90cUWtNKh_0QGYVE"
puts ""
