# Keycloak Integration Options for TMCP Server

## Option 1: Delegate OAuth to Keycloak (Recommended)
Instead of implementing custom OAuth, configure TMCP Server to use Keycloak as the OAuth provider.

### Configuration Changes:
1. Remove custom OAuth controller
2. Configure routes to proxy to Keycloak
3. Store Keycloak client credentials
4. Validate tokens issued by Keycloak

### TMCP Server as Keycloak Client:
```ruby
# config/initializers/keycloak.rb
Rails.application.config.keycloak = {
  server_url: ENV['KEYCLOAK_URL'] || 'https://keycloak.example.com',
  realm: ENV['KEYCLOAK_REALM'] || 'tmcp',
  client_id: ENV['KEYCLOAK_CLIENT_ID'] || 'tmcp-server',
  client_secret: ENV['KEYCLOAK_CLIENT_SECRET']
}
```

## Option 2: Keycloak as Identity Provider
Keep TMCP OAuth flow but authenticate users through Keycloak.

### Implementation:
1. During authorization, redirect to Keycloak login
2. After Keycloak authentication, proceed with TMCP authorization code flow
3. Issue TEP tokens based on Keycloak JWT

## Option 3: Hybrid Approach
Use Keycloak for user authentication while maintaining TMCP-specific OAuth scopes and TEP tokens.

### Benefits:
- Leverages Keycloak's user management and security features
- Maintains TMCP protocol compliance
- Supports advanced Keycloak features (social login, MFA, etc.)

## Recommended Integration Path:

1. **Configure Keycloak Realm** for TMCP with custom scopes
2. **Replace TMCP OAuth controller** with Keycloak delegation
3. **Update TEP token generation** to include Keycloak user info
4. **Maintain TMCP scope validation** alongside Keycloak permissions

## Keycloak-Compatible TMCP Scopes:
```
# Keycloak client scopes
user:read
user:read:extended
user:read:contacts
wallet:balance
wallet:pay
wallet:history
messaging:send
messaging:read
storage:read
storage:write
```