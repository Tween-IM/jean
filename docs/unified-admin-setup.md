# Running Tween Admin

Tween Admin is implemented inside Jean. The browser uses Jean's Rails session and
one interface; Jean calls the other services on the server. Existing commerce,
mini-app, OAuth and catalog screens stay in the same workspace. No backend admin
UI is embedded or used as a browser redirect for routine work.

## Implemented

- Redesigned responsive shell, overview, people search, account detail tabs,
  shared resource tables, record details, action forms and activity history.
- Existing commerce and platform workflows remain in place, under the new shell.
- Payment resource lists/details: wallets, transactions, pending transfers,
  businesses, bank accounts, pockets, stashes, compliance reviews, bills, API keys,
  webhooks and notifications. Responses use explicit field allowlists.
- Payment commands: explicit wallet status, pending-transfer cancellation,
  compliance review, API-key revocation, webhook state/failure reset. Commands
  require a reason and a stable UUID and are deduplicated in Tween Pay.
- Messaging room/report list/detail, room blocking/unblocking and report dismissal.
- Linked MAS identity detail and account locking/unlocking.
- Independent tab failures, direct-request permission checks, short-lived signed
  payment staff delegation, backend staff revocation checks and durable audits.
- Production login fails closed without an emergency token; production staff MFA
  is required by default. Pending MFA expires after ten minutes.

## Local verification

Use Ruby 3.4.4 and the installed bundle in each repository. Run Jean's migration
and CSS build, then start the normal Rails server:

```sh
bin/rails db:migrate
bin/rails tailwindcss:build
bin/rails server
```

Open `/admin/login`. Configure the connections below to enable remote data; the
profile and existing local workflows do not depend on those services responding.
The dedicated hostname root routes to the same overview. Existing `/admin/...`
URLs continue to work.

## Configuration

| Location | Setting | Purpose |
| --- | --- | --- |
| Jean | `ADMIN_HOST` | Dedicated staff hostname; defaults to `admin.tween.im` |
| Jean | `MAS_AUTH_URL` or `MAS_URL` | Existing staff OIDC issuer |
| Jean | `MAS_CLIENT_ID`, `MAS_CLIENT_SECRET` or `MAS_CLIENT_SECRET_FILE` | Existing staff OIDC client |
| Jean | `MAS_ADMIN_REDIRECT_URI` | Register `https://admin.tween.im/admin/auth/mas/callback` on the staff OIDC client |
| Jean | `ADMIN_REQUIRE_MFA` | Defaults to `true` in production; enroll staff authenticators before cutover |
| Jean | `ADMIN_ACCESS_TOKEN` | Optional explicitly configured emergency access; store as a secret |
| Jean | `TWEEN_PAY_ADMIN_URL` | Optional HTTPS base URL override; defaults to existing `WALLET_API_BASE_URL`, without `/internal/admin/v1` |
| Both | `TWEEN_ADMIN_SECRET` | Dedicated shared signing secret of at least 32 bytes, supplied through secret configuration |
| Jean | `SYNAPSE_ADMIN_URL`, `SYNAPSE_ADMIN_TOKEN` | Optional Synapse URL override (defaults to existing `MATRIX_API_URL`), plus the required server-admin credential |
| Jean | `MAS_ADMIN_CLIENT_ID`, `MAS_ADMIN_CLIENT_SECRET` | Dedicated privileged client; when no static token is set, Jean obtains a fresh `urn:mas:admin` access token using client credentials |
| Jean | `MAS_ADMIN_URL`, `MAS_ADMIN_TOKEN` | Optional MAS URL override (defaults to existing `MAS_AUTH_URL` / `MAS_URL`) and an optional admin-scoped access token; refresh/rotate before expiry |

The MAS staff login client is distinct from the privileged MAS API credential.
No administrative tokens go into JavaScript, browser storage, or HTML. Production
upstream URLs require HTTPS. Connection credentials are never displayed by the UI.

Before enabling payment access, create/link the staff identity in Tween Pay with
the same full Matrix ID and deliberately assign its local staff role. A Jean role
alone grants no access to Tween Pay. The backend checks the active user and local
permissions on every request. Jean's finance-analyst role intentionally cannot
change wallet status even though the preexisting Tween Pay policy permits it.

No service account is provisioned during reads. Payment identity is resolved by
full Matrix ID; Jean's locally derived wallet ID is not used as a cross-database
join. Missing payment/identity links are shown as unavailable, never as a zero
balance or a newly provisioned account.

## Deployment order

1. Deploy Tween Pay's internal API and run its `admin_workspace_commands`
   migration. Restrict `/internal/admin/v1` at the network/proxy layer to the
   dashboard server where possible; signed authentication is still required.
2. Configure the same dedicated signing secret in both services. Configure the
   Synapse and MAS credentials and verify staff mappings/roles.
3. Deploy Jean, run the `admin_audit_events` migration, and build its CSS. Verify
   staff have enrolled MFA before applying the production default requirement.
4. Register the dedicated-host callback and verify login/logout, denied access,
   reads, unavailable states, and a controlled command in staging.
5. Route `admin.tween.im` to Jean only after validating the required workflow
   coverage. Preserve a restricted engineering fallback for the old admin tools.

No production host or DNS/proxy routing was changed by this local implementation.
Do not grant every staff member a super-admin role to make a connection work.

## Scope still requiring migration before full retirement of old tools

The unified dashboard is functional, but this is not complete parity with every
old admin tool. These operations are intentionally not exposed as placeholder
buttons: payment-user status/role editing and KYC reset, business provisioning,
pocket/stash refund/reversal commands, general MAS client/provider/session
management, media moderation, and advanced Synapse maintenance. Existing
engineering consoles remain fallback tools until those workflows are migrated.

Search currently covers Jean's people directory. Payment and MAS details use
existing identity links; searching MAS-only or unlinked payment accounts is not
implemented. MAS API access uses a dedicated client-credentials grant or a supplied token. Missing links and expired credentials do not
trigger provisioning or broaden permissions.

Audit records cover new remote commands and existing local actions that call
`log_admin_action`. Historical application logs are not backfilled into the new
activity table. Upstream timeouts produce an `unknown` audit outcome; inspect the
backend outcome before retrying a non-idempotent operation. Payment retries with
the same UUID and same payload return the stored outcome.

## Checks

Jean:

```sh
bin/rails zeitwerk:check
bin/rails test test/integration/admin/ test/controllers/admin/ test/services/admin_remote_client_test.rb
bin/rails tailwindcss:build
```

Tween Pay:

```sh
bin/rails zeitwerk:check
TYPELIZER=false bundle exec rspec spec/requests/internal/admin/workspace_spec.rb
```

Browser review: overview, people, person workspace at 1440px and 390px; confirm
menu operation, no page-wide overflow, keyboard focus and error states. Local
preview screenshots are under `tmp/admin-preview/` and are not committed assets.
