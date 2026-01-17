# Matrix Application Service Authentication Setup

## Required Environment Variables

The TMCP Server requires these Matrix AS-specific environment variables to be set:

### 1. MATRIX_HS_TOKEN (Required)

**Purpose:** Token used by Synapse homeserver to authenticate when sending events to TMCP Server

**How it works:**
- Synapse includes this token in `Authorization: Bearer {MATRIX_HS_TOKEN}` header
- TMCP Server validates this token before processing Matrix events
- Must match the `hs_token` in Synapse AS registration file

**How to generate:**
```bash
# Generate random 64-character hex string
openssl rand -hex 32
```

**How to configure:**
```yaml
# In your Synapse AS registration file (e.g., /data/tmcp-registration.yaml)
id: "tmcp"
url: "https://tmcp.tween.im/_matrix/app/v1"
as_token: "your_as_token_here"
hs_token: "your_hs_token_here"  # This must match MATRIX_HS_TOKEN env var
sender_localpart: "_tmcp"
namespaces:
  users:
    - exclusive: true
      regex: "@_tmcp:*"
```

```bash
# In your TMCP Server environment (docker-compose.yml, .env, or Kubernetes)
export MATRIX_HS_TOKEN="your_hs_token_here"
```

**Verification:**
```bash
# Test AS authentication
curl -X POST https://tmcp.tween.im/_matrix/app/v1/ping \
  -H "Authorization: Bearer $MATRIX_HS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"transaction_id": "test"}'

# Should return: {} with 200 OK
# If returns 401, token doesn't match
```

---

### 2. MATRIX_AS_TOKEN (Required)

**Purpose:** Token used by TMCP Server to authenticate with Synapse Client-Server API

**How it works:**
- TMCP Server uses this token to make requests to Matrix API
- Used for: joining rooms, sending messages, inviting users
- Must match the `as_token` in Synapse AS registration file

**How to generate:**
```bash
# Generate random 64-character hex string
openssl rand -hex 32
```

**How to configure:**
```yaml
# In your Synapse AS registration file
as_token: "your_as_token_here"  # This must match MATRIX_AS_TOKEN env var
```

```bash
# In your TMCP Server environment
export MATRIX_AS_TOKEN="your_as_token_here"
```

**Verification:**
```bash
# Test AS token works with Synapse
curl -X GET https://core.tween.im/_matrix/client/v3/account/whoami \
  -H "Authorization: Bearer $MATRIX_AS_TOKEN"

# Should return: {"user_id": "@_tmcp:tween.im"}
```

---

### 3. MATRIX_API_URL (Optional, has default)

**Purpose:** URL of Matrix homeserver Client-Server API

**Default value:** `https://core.tween.im`

**How to configure:**
```bash
export MATRIX_API_URL="https://core.tween.im"
```

---

## Complete Setup Process

### Step 1: Generate Tokens

```bash
# Generate both tokens
HS_TOKEN=$(openssl rand -hex 32)
AS_TOKEN=$(openssl rand -hex 32)

echo "HS_TOKEN: $HS_TOKEN"
echo "AS_TOKEN: $AS_TOKEN"
```

### Step 2: Configure Synapse AS Registration

Create/update `/data/tmcp-registration.yaml`:

```yaml
id: "tmcp"
url: "https://tmcp.tween.im/_matrix/app/v1"
as_token: "${AS_TOKEN}"  # Replace with generated AS_TOKEN
hs_token: "${HS_TOKEN}"  # Replace with generated HS_TOKEN
sender_localpart: "_tmcp"
namespaces:
  users:
    - exclusive: true
      regex: "@_tmcp:*"
  aliases: []
  rooms: []
```

### Step 3: Reload Synapse Configuration

```bash
# Synapse will automatically reload when registration file changes
# Or force reload:
docker exec synapse killall -HUP synapse
```

### Step 4: Configure TMCP Server Environment

Add to `docker-compose.yml`:

```yaml
services:
  tmcp-server:
    environment:
      - MATRIX_HS_TOKEN=${HS_TOKEN}  # From step 1
      - MATRIX_AS_TOKEN=${AS_TOKEN}  # From step 1
      - MATRIX_API_URL=https://core.tween.im
```

Or to `.env` file:

```bash
MATRIX_HS_TOKEN=your_hs_token_here
MATRIX_AS_TOKEN=your_as_token_here
MATRIX_API_URL=https://core.tween.im
```

### Step 5: Restart TMCP Server

```bash
# If using docker-compose
docker-compose restart tmcp-server

# Or if running Rails directly
# Kill and restart the Rails server
```

---

## Troubleshooting

### Issue: "401 Unauthorized" from TMCP Server

**Symptoms:**
- Synapse logs show authentication failures
- TMCP Server returns 401 for `/ping` or `/transactions` endpoints

**Solutions:**
1. Verify `MATRIX_HS_TOKEN` is set in TMCP Server environment:
   ```bash
   docker exec tmcp-server env | grep MATRIX_HS_TOKEN
   ```

2. Check `hs_token` in Synapse registration matches `MATRIX_HS_TOKEN`:
   ```bash
   cat /data/tmcp-registration.yaml | grep hs_token
   ```

3. Restart TMCP Server after changing environment variables

4. Check TMCP Server logs:
   ```bash
   docker logs tmcp-server | grep "unauthorized"
   ```

### Issue: Bot users don't join rooms

**Symptoms:**
- Bot shows as "invited" but never joins
- No error messages

**Solutions:**
1. Verify `MATRIX_AS_TOKEN` is set:
   ```bash
   docker exec tmcp-server env | grep MATRIX_AS_TOKEN
   ```

2. Check `as_token` in Synapse registration matches `MATRIX_AS_TOKEN`:
   ```bash
   cat /data/tmcp-registration.yaml | grep as_token
   ```

3. Test AS token works:
   ```bash
   curl -X GET https://core.tween.im/_matrix/client/v3/account/whoami \
     -H "Authorization: Bearer $MATRIX_AS_TOKEN"
   ```

4. Check TMCP Server is processing invite events:
   ```bash
   docker logs tmcp-server | grep "invited to room"
   ```

### Issue: Duplicate method definitions causing errors

**Symptoms:**
- Strange behavior from endpoints
- Methods returning wrong responses
- Rails errors about method redefinition

**Solution:**
The `matrix_controller.rb` file has been fixed to remove duplicates. Ensure you're using the corrected version.

### Issue: Matrix user queries return wrong format

**Symptoms:**
- User queries return detailed JSON instead of empty body
- Matrix clients fail to use TMCP users

**Solution:**
The `user` endpoint now returns Matrix-compliant responses:
- `200 OK` with `{}` when user exists
- `404 Not Found` with `{}` when user doesn't exist

---

## Testing Matrix AS Integration

### 1. Test AS Health Check

```bash
HS_TOKEN="your_hs_token_here"

curl -X POST https://tmcp.tween.im/_matrix/app/v1/ping \
  -H "Authorization: Bearer $HS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"transaction_id": "test"}'

# Expected: {} with 200 OK
```

### 2. Test User Query

```bash
curl https://tmcp.tween.im/_matrix/app/v1/users/@_tmcp:tween.im

# Expected: {} with 200 OK
```

### 3. Invite Bot to Room

```bash
# Via Matrix client (Element), invite @_tmcp:tween.im to a room
# Then check logs:
docker logs tmcp-server | grep "invited to room"

# Bot should auto-join automatically
```

### 4. Test Bot Profile

```bash
curl https://core.tween.im/_matrix/client/v3/profile/@_tmcp:tween.im

# Expected: Profile exists (no 404)
```

---

## Security Notes

1. **Never commit tokens to git** - Always use environment variables
2. **Use strong random tokens** - 64-character hex strings
3. **Rotate tokens regularly** - Every 30-90 days
4. **Monitor logs** - Watch for authentication failures
5. **Use HTTPS** - All Matrix API communication must be encrypted

---

## References

- Matrix AS API v1.11: https://spec.matrix.org/v1.11/application-service-api/
- Synapse AS Registration: https://element-hq.github.io/synapse/latest/application_services.html
- TMCP Protocol: /config/workspace/jean/docs/PROTO.md
