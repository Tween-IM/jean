# Tween Admin: feature inventory and implementation plan

Status: baseline audit and implementation plan, 15 November 2026.
The initial unified dashboard is implemented locally; see `unified-admin-setup.md`
for implemented features, verification, configuration and remaining migration scope.
Scope: rebuild the staff interface inside Jean; integrate Tween Pay, Synapse and
MAS through server-side APIs. This document does not change production behavior.

## Decision and boundaries

Jean hosts Tween Admin at `admin.tween.im`. Its existing `/admin` namespace is the
starting point. No new Rails application, shared database, or iframe wrapper.
Jean retains its existing public API and commerce responsibilities. Tween Pay
owns financial rules and mutations; Synapse owns Matrix room operations; MAS owns
identity and authentication sessions. MAS and Synapse are separate integrations.

The staff interface is an internal operational surface. Keep it separate from
TMCP mini-app authentication and payment protocol contracts in `docs/PROTO.md`
(especially sections 1.3 and 4). Do not extend client TEP scopes or reuse a user's
payment authorization to grant staff privileges.

## Baseline before implementation

Inventory is based on local source, not a claim that every endpoint works in the
currently deployed revisions. Routes and controllers were both inspected.

### Jean

Sources: `config/routes.rb`, `app/controllers/admin`, `app/models/user.rb`,
`app/services/admin/mas_oidc.rb`, `app/views/layouts/admin.html.erb`.

| Surface | Existing operations | Current permission behavior |
| --- | --- | --- |
| Dashboard | User, mini-app and commerce metrics; attention queues | Any platform staff; metrics need per-section filtering |
| Users | List, detail, status and platform-role edits; installations, storage, MFA methods | Reads use base staff gate; edits require `manage_users` |
| Mini-apps | List, detail, create, edit, update, delete, hard-delete | Reads use base staff gate; writes require `manage_mini_apps` |
| Mini-app reviews | Queue, detail, approve, reject, request changes, resolve appeal | Base staff gate; action-specific checks need explicit coverage |
| OAuth applications | List, detail, token/grant listings, delete | Reads use base staff gate; delete requires `manage_oauth` |
| Orders | List, detail, transition, refund, fulfillment and payment actions | `view_orders`, `manage_orders`, `manage_refunds` |
| Sourcing/procurements | List, detail, advance | `view_fulfillment`, `manage_fulfillment` |
| Stores | List, detail, update, enrich, feature | `view_storefronts`, `manage_storefronts` |
| Products and SKUs | List, detail, update, media, SKU update | `view_catalog`, `manage_catalog` |
| Merchants | List, detail, update, verify, suspend, reactivate | `view_merchants`, `manage_merchants` |
| Categories | List, create, update, prune empty | `view_categories`, `manage_categories` |
| Imports | Overview; system merchant; imported stores/products/reviews | `view_imports`, `manage_imports` |

Existing roles: support, compliance officer/manager, operations analyst/manager,
super admin, plus `none`. Super admin bypasses individual permission checks.
Commerce reads cover support, operations and compliance; most commerce writes
require operations manager. Refund permission also includes compliance manager.
Some named permissions in the model are not enforced by the corresponding read
controllers. Treat the controller behavior above separately from intended policy.

### Tween Pay

Sources: `config/routes.rb`, `app/controllers/admin`, `app/models/user.rb`,
`app/models/admin_audit_log.rb`, `lib/blazer_access_constraint.rb`.

| Surface | Existing operations | Current permission behavior |
| --- | --- | --- |
| Dashboard | Financial metrics, pending compliance, recent transactions/audit | Base staff gate; no per-widget checks in controller |
| Users | List, detail, edit, update, reset KYC | `view_users`; writes default to `manage_users` |
| Transactions | List, detail | `view_transactions` |
| Compliance | List, detail, edit, review update | `view_kyc`; edits/update use `approve_kyc` |
| Businesses | List, detail, new, create | `view_businesses`, `manage_businesses` |
| Wallets | List, detail, toggle status | `view_wallets`, `manage_wallets` |
| Bank accounts | List, detail | `view_bank_accounts` |
| API keys | List, detail, revoke | `view_api_keys`, `manage_api_keys` |
| Webhooks | List, detail, enable/disable, reset failures | `view_webhooks`, `manage_webhooks` |
| Bills | List, detail | `view_bills` |
| Notifications | List, detail | `view_notifications` |
| Pending transfers | List, detail, cancel | `view_pending_transfers`, `manage_pending_transfers` |
| Audit logs | List | `view_audit` |
| Pockets and stashes | JSON list/detail, reverse transaction, refund balance | Nested account controllers use base staff gate; routing and finer permissions need repair |
| Blazer | Mounted SQL analytics tool | Finance analyst/manager or super admin |
| Sidekiq | Conditional operations UI | Separate operational authentication/configuration; retain as engineering tool |

Tween Pay additionally has risk analyst/manager, finance analyst/manager and
product manager roles. The same role name does not imply identical permissions
across the two services. For example, Jean's model restricts `view_users` to super
admin, whereas Tween Pay's model allows all staff. Finance analysts currently
have `manage_wallets`; preserve no such grant implicitly during migration.

The ordinary payment admin controllers are browser/session controllers, not a
service-to-service admin API. Some nested controllers render JSON, but still
inherit browser-session authentication. Do not call these by forwarding cookies.

The routes declare `resources :pockets` and `resources :stashes`, while the
controllers live at `Admin::Pockets::AccountsController` and
`Admin::Stashes::AccountsController`. Validate and repair that mismatch before
claiming parity. Their audit/error helper calls also need verification against
`Admin::BaseController` before exposing money movement in the new UI.

### Synapse and MAS

Use the checked-in API implementations and documentation as the endpoint source
of truth; validate against the deployed version before enabling each capability.

| Service | Candidate admin coverage | Source |
| --- | --- | --- |
| Synapse | User inspection, devices, account actions | `../synapse/docs/admin_api/user_admin_api.md` |
| Synapse | Rooms, membership, moderation operations | `../synapse/docs/admin_api/rooms.md`, `room_membership.md` |
| Synapse | Reports and media moderation | `../synapse/docs/admin_api/event_reports.md`, `media_admin_api.md` |
| Synapse | Statistics, notices and version | `../synapse/docs/admin_api/statistics.md`, `server_notices.md`, `version_api.md` |
| MAS | Users, emails, account lifecycle | `../tween-auth/crates/handlers/src/admin/v1/users`, `user_emails` |
| MAS | User, OAuth, personal and compatibility sessions | Sibling modules under `admin/v1` |
| MAS | OAuth clients/providers, registration tokens, policy/config/version | Sibling modules under `admin/v1` |

This is candidate API coverage, not an audited inventory of every Element Admin
screen. Identity changes must respect delegated authentication: do not assume a
Synapse account action revokes MAS sessions or changes MAS credentials.

## Authentication, authorization and identity

Jean already supports MAS authorization code with PKCE and maps userinfo `sub`
to `mas_user_id`, with a Matrix ID fallback. Its staff login additionally requires
a local platform role and active status. Optional local TOTP is supported.
Tween Pay currently uses email/password, optional TOTP and its own staff session.
Both have inactivity timeouts. MFA is currently optional, not universally enforced.

Before expanding access:

1. Make MAS login the normal staff entry point. Require MFA for staff. Keep any
   emergency login explicit, configured and restricted; Jean's existing token
   path currently skips token validation when `ADMIN_ACCESS_TOKEN` is unset.
2. Rotate the session after authentication and MFA completion; check active staff
   status and session expiry consistently, including MFA pending-session expiry.
3. Define explicit capabilities per domain, such as `payments.wallets.read`,
   `payments.wallets.freeze`, `payments.kyc.review`, `messaging.rooms.moderate` and
   `identity.sessions.revoke`. Map existing roles deliberately; no automatic
   privilege union and no UI-only authorization.
4. Jean checks capabilities before calls. Tween Pay independently verifies a
   dedicated service credential and authenticated staff delegation, including
   its own grants/revocation. Never trust an unsigned actor ID/role header.
5. Synapse/MAS privileged credentials stay server-side. Where upstream APIs lack
   fine-grained delegation, Jean must enforce the narrower capability before
   every call and record the actor; do not claim upstream staff-level enforcement.

Use full Matrix IDs to correlate existing records, and MAS subject IDs for
identity links where available. Never join local primary keys, email addresses,
or derived `tw_<id>` wallet IDs across databases. Jean generates a wallet ID from
its own local ID today; Tween Pay also derives IDs from its own users. Resolve the
actual payment user/wallet mapping through a read-only API. Do not use a resolver
that provisions users or wallets while merely viewing an admin page. Support
missing links, MAS-only users and payment users without a Matrix identity.

## Integration design

Keep UI controllers in Jean under `Admin`. Add server-side clients under
`TweenPay::AdminClient`, `Matrix::AdminClient`, and `Mas::AdminClient`. Keep service
URLs fixed in configuration; encode external identifiers as path segments.

Add a versioned internal Tween Pay admin API, separate from browser `/admin`
routes and client TMCP endpoints. Initial contracts: read-only user lookup by
Matrix ID, payment-user detail, paginated wallets/transactions and service status.
Follow with explicit commands for existing operations; factor shared business
logic into Tween Pay services instead of copying controller mutations into Jean.

Use short bounded timeouts, stable error responses, pagination and request IDs.
Read panels fail independently and show unavailable/last-updated states rather
than zero balances. Retry safe reads only. Financial commands require backend
authorization, validation, idempotency, reason and an attributable audit outcome.
Cross-service account suspension is a visible sequence of independent actions,
not a pretend distributed transaction; surface partial completion and recovery.

Jean currently writes audit entries to application logs; Tween Pay persists an
`AdminAuditLog`. Add durable Jean audit events for staff commands, role changes
and sensitive access. Record actor, service, target, action, reason, request ID,
time and pending/success/failure/unknown outcome. Retain backend records and
correlate them. Do not log tokens, document payloads or unrestricted request params.

## UI overhaul — required implementation scope

Replace the legacy presentation, not merely its brand name. Reuse business logic
and useful content, while rebuilding layouts and page components. Current Jean
uses ERB, Tailwind, Inter and icon helpers; continue with Rails-rendered views and
shared components/partials unless a concrete interaction needs JavaScript.

Proposed navigation:

- Overview: role-filtered attention queues and service availability.
- People: unified search and a user workspace.
- Commerce: orders, sourcing, stores, products, merchants, categories, imports.
- Payments: wallets, transactions, pending transfers, pockets, stashes, businesses.
- Compliance: KYC reviews and relevant case information.
- Messaging: rooms, reports and media moderation.
- Platform: mini-apps, reviews, OAuth clients and integration operations.
- Administration: staff access and audit history.

Design a calm, compact operational workspace: neutral surfaces, clear typography,
a restrained accent, consistent spacing, semantic status colors with text labels,
and a responsive collapsible sidebar. Prioritize information hierarchy over
cards and decoration. No backend switching or technical implementation labels
in ordinary staff flows. Keep engineering tools separate and access-restricted.

The user workspace has an identity summary and capability-filtered tabs for
profile, commerce, payments, messaging, sessions and activity. Clearly distinguish
Jean status, payment restrictions, Synapse status and MAS status; a single badge
must not conceal disagreement between services.

Build shared page headers, breadcrumbs, tables, filters, pagination, tabs, status
badges, form fields, validation messages, drawers/dialogs and audit timelines.
Filters live in URLs. Tables have consistent sorting, row actions and useful empty
states. Provide loading, unavailable, forbidden and retry states. Preserve filters
and return context after actions. Confirm destructive actions with their actual
effect and target; money and account actions collect a reason and show outcomes.

Keyboard navigation, visible focus, labeled controls, contrast, narrow-screen
layouts, large data sets and long Matrix IDs are part of acceptance. Use real
backend data in implemented screens; no fabricated metrics or enabled placeholder
actions. MFA and authorization belong in working flows, not decorative screens.

## Delivery order and acceptance

| Stage | Deliverable | Acceptance |
| --- | --- | --- |
| 1. Foundation | Shared capability policy, staff login/session fixes, durable audit, redesigned shell and reusable components | Authorization tests cover direct requests and role revocation; authenticated/unauthenticated layouts render; keyboard and responsive review |
| 2. People | Search and redesigned user detail; authenticated read-only payment/Synapse/MAS adapters | Correct cross-service links; no accidental provisioning; permission-filtered fields; independent unavailable states |
| 3. Jean workflows | Migrate all existing commerce, mini-app and OAuth screens into the new components | Every route/action in inventory covered or explicitly retired; controller permissions enforced; existing operations still work |
| 4. Payment workflows | Internal admin API and new Jean payment/compliance screens, then controlled mutations | Backend rejects forged/missing delegation; amounts/currency preserved; idempotency and audit attribution verified |
| 5. Messaging and identity | Rooms/reports/media and MAS account/session workflows | Each destructive action tested against supported upstream APIs; partial failures visible; secrets absent from browser |
| 6. Cutover | Route `admin.tween.im` to Jean and restrict former dashboards | Registered MAS callback works; assets/cookies/CSRF work on hostname; engineering fallback and rollback verified |

Do not repoint `admin.tween.im` at the shell-only stage: it currently hosts Element
Admin. Keep it available during migration, then retain an engineering-only fallback
at an agreed protected location. Existing Jean routes should keep working through
the migration; backend admin UIs remain restricted fallback tools until parity.

Use Rails integration tests for auth/capabilities and staff workflows, client
contract tests for upstream errors, and meaningful payment service tests for
commands. Visually review the shell, overview, user workspace, a dense table and
an action form at desktop and narrow widths. A documentation/source audit alone
is not runtime, deployment or UI verification.
