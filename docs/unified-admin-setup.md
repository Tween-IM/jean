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
- Per-admin MAS authorization with encrypted, session-bound credentials and refresh rotation.
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
| Jean | `SYNAPSE_ADMIN_URL` | Optional URL override; defaults to existing `MATRIX_API_URL`. No global admin token is used. |
| Jean | `MAS_ADMIN_URL` | Optional API URL override; defaults to existing `MAS_AUTH_URL` / `MAS_URL`. |

Messaging and identity administration use the signed-in staff member's own MAS
OAuth grant, not a shared user, application-service token or client-credentials
administrator. Legacy `SYNAPSE_ADMIN_TOKEN`, `MAS_ADMIN_TOKEN` and
`MAS_ADMIN_CLIENT_*` variables are ignored by these integrations and should be
removed from deployment.

Ordinary Tween ID login continues to request only `openid`. On entering an
administrative section, choose **Authorize with Tween ID**. The existing MAS
client and registered callback are reused with authorization code + PKCE,
requesting `openid urn:matrix:client:api:* urn:synapse:admin:* urn:mas:admin`.
MAS decides whether that person can receive those privileges. A Jean staff role
alone does not grant MAS administration rights. Staff denied those scopes retain
their other permitted workspace sections; do not promote accounts automatically.

The callback must name the exact MAS subject linked to the current staff account.
An authorization is scoped to one browser's staff session, never shared with
another staff member or browser. Only a random opaque reference goes in the Rails
session cookie. Access/refresh tokens are encrypted in the database with a key
derived from the existing Rails secret key base; no new encryption env is needed.
Refresh is serialized by a row lock and persists rotated refresh tokens. Logout,
idle expiry, upstream rejection, identity changes and role revocation clear local
access. Remote revocation is attempted on disconnect. There is a twelve-hour
absolute grant lifetime before new consent is required.

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

1. Deploy Tween Pay's internal API and run its `admin_workspace_commands` and `admin_savings_reversals`
   migration. Restrict `/internal/admin/v1` at the network/proxy layer to the
   dashboard server where possible; signed authentication is still required.
2. Configure the same dedicated signing secret in both services. Verify staff mappings/roles and each administrator's own MAS permissions.
3. Deploy Jean, run the `admin_audit_events` and `admin_oauth_grants` migrations, and build its CSS. Verify
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
buttons: payment-user status/role editing, business provisioning,
general MAS client/provider/session
management, media moderation, and advanced Synapse maintenance. Existing
engineering consoles remain fallback tools until those workflows are migrated.

Search currently covers Jean's people directory. Payment and MAS details use
existing identity links; searching MAS-only or unlinked payment accounts is not
implemented. MAS and Synapse API access require per-admin consent. Missing links and expired credentials do not
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

## Evidence and card operations

On Tween Pay, set `IDENTITY_DOCUMENT_ALLOWED_HOSTS` to a comma-separated list of
exact HTTPS storage hostnames used for identity uploads (no schemes or paths).
Private-network hosts and redirects are rejected. This setting is required for
evidence viewing and document approval, not for dashboard login or ordinary reads.
Do not use a wildcard. Document approval requires the same staff member to view
the current evidence version first.

Card issuance uses existing Clover credentials and current reviewed issuance
quotes. No new Jean URL or card-provider credential is needed. Provider timeouts
retain command receipts: use reconciliation from the payment account, or refresh
the existing card, before submitting another provider change.


### Verification review evidence

Use **Compliance → Verification reviews** for the durable BVN, NIN and face-check submission history, including failed checks. Customer → Compliance links to the same records. Screening checks remain separate provider/risk screening records; Customer KYC status shows the current granted status, not submission history.

Authorized compliance staff can inspect encrypted submissions, the exact retained provider HTTP body and status, provider identity photos, the identity reference used for comparison, final selfie and three challenge frames. Images use authenticated, audited, non-cached endpoints. No new environment variable is required: encryption derives from the existing stable Rails secret; preserve that secret with database backups. Never rotate it without migrating retained evidence.

Manual approval or keeping a rejection requires a reason and acknowledgement of the exact evidence version. Original machine/provider outcomes remain unchanged. Reviews record the operator, time, reason and evidence digest. Approval uses existing KYC tier eligibility/provisioning and does not repeat a paid provider lookup. Superseded identities and incomplete face captures cannot be approved; request a new submission. Rejection of an old failed attempt does not revoke a subsequent valid identity grant.

Retention begins with this release. Historical provider exchanges can be imported from retained application logs via `VerificationHistoryImporter`; missing historical selfies cannot be reconstructed. Empty galleries explain when no photo was returned or retained. Biometric payloads over 16 MB are marked as omitted rather than silently treated as evidence. Include this encrypted table in your controlled KYC retention/deletion policy.
